import json,os,pathlib,subprocess,sys,signal,time,urllib.request
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
from simulator_boot import boot
# No proxy or redirect may carry synthetic credentials outside this runner.
class NoRedirect(urllib.request.HTTPRedirectHandler):
 def redirect_request(self, req, fp, code, msg, headers, newurl):
  raise RuntimeError('Isolated endpoint redirected')
opener=urllib.request.build_opener(urllib.request.ProxyHandler({}),NoRedirect())
phase='initialization'
def checkpoint(value):
 global phase
 phase=value
 result['phase']=phase
 result.setdefault('phases',[]).append({'phase':value,'time':time.time()})
 (root/'integration-result.json').write_text(json.dumps(result,indent=2))
def authenticate_owner(context):
 request=urllib.request.Request('http://127.0.0.1:61812/api/i',data=json.dumps({'i':context['adminToken']}).encode(),headers={'Content-Type':'application/json'})
 with opener.open(request,timeout=15) as response:
  owner=json.load(response)
 assert owner.get('isAdmin') is True and owner.get('username')=='isolated_owner'

root=pathlib.Path('build');root.mkdir(exist_ok=True)
inventory=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','--json']))['devices']
runtime='com.apple.CoreSimulator.SimRuntime.iOS-26-0'
assert runtime in inventory, 'The baseline iOS 26.0 runtime is required; do not silently use another runtime'
devices=[dict(d,runtime=runtime) for d in inventory[runtime] if d['name'].startswith('iPhone')]
template=next(d for d in devices if d['name']=='iPhone 17 Pro Max')
device=subprocess.check_output(['xcrun','simctl','create','PUBO real backend',template['deviceTypeIdentifier'],template['runtime']],text=True).strip()
result={'status':'RUNNING','device':template['name'],'runtime':template['runtime'],'productionAPIRequests':0,'transport':'loopback-only real backend'}
try:
 checkpoint('context-before-simulator')
 with opener.open('http://127.0.0.1:61913/context',timeout=15) as response:
  context=json.load(response)
 # Distinguish an already-unhealthy backend from a failure caused during simulator boot.
 # Two distinct checkpoints, not a retry of a failed request. Both must pass.
 checkpoint('owner-auth-before-simulator')
 authenticate_owner(context)
 checkpoint('simulator-boot')
 boot(device,root/'integration-boot.json')
 checkpoint('owner-auth-after-simulator')
 authenticate_owner(context)
 result['ownerAPIAuthenticated']=True
 checkpoint('install')
 subprocess.run(['xcrun','simctl','install',device,'build/integration-derived/Build/Products/Debug-iphonesimulator/PUBO.app'],check=True,timeout=300)
 checkpoint('simulator-app-warmup')
 warm=subprocess.run(['xcrun','simctl','launch',device,'com.bolubo.native','--isolated-backend'],check=True,timeout=60,capture_output=True,env={**os.environ,'SIMCTL_CHILD_PUBO_ISOLATED_TOKEN':context['adminToken']})
 del context,warm
 time.sleep(12)
 subprocess.run(['xcrun','simctl','terminate',device,'com.bolubo.native'],check=True,timeout=30)
 result['simulatorWarmup']='Completed separate setup launch and termination'
 command=['xcodebuild','-quiet','-project','PUBO.xcodeproj','-scheme','PUBO','-configuration','Debug','-destination','platform=iOS Simulator,id='+device,'-derivedDataPath','build/integration-derived','-resultBundlePath','build/integration-ui.xcresult','-parallel-testing-enabled','NO','-only-testing:PUBOUITests/PUBOIntegrationTests','-only-testing:PUBOUITests/ReconnectionUITests','CODE_SIGNING_ALLOWED=NO','test']
 notification_test = os.environ.get('PUBO_CHECK_NOTIFICATIONS') == '1'
 if notification_test:
  command.insert(-1, '-only-testing:PUBOUITests/NotificationBackendTests')
 (root/'integration-screenshots').mkdir(exist_ok=True)
 recording={'startedAt':time.time(),'file':'integration-screenshots/interactions.mp4'}
 (root/'integration-recording.json').write_text(json.dumps(recording))
 video=subprocess.Popen(['xcrun','simctl','io',device,'recordVideo','--codec=h264',str(root/'integration-screenshots/interactions.mp4')])
 checkpoint('native-tests')
 subprocess.run(command,check=True,timeout=1500,env={**os.environ,'TEST_RUNNER_PUBO_REQUIRE_ISOLATED_BACKEND':'1','TEST_RUNNER_PUBO_CHECK_NOTIFICATIONS':str(int(notification_test))})
 summary=json.loads(subprocess.check_output(['xcrun','xcresulttool','get','test-results','summary','--path','build/integration-ui.xcresult']))
 (root/'integration-test-summary.json').write_text(json.dumps(summary,indent=2))
 assert summary.get('passedTests',0)==21+int(notification_test) and summary.get('failedTests',0)==0 and summary.get('skippedTests',0)==0, 'Every selected real-backend UI test must run and pass'
 result['status']='PASS'
except Exception as error:
 result['status']='FAIL';result['error']=type(error).__name__+': '+str(error)
 # Capture the synthetic simulator screen on setup failures without printing tokens.
 try:
  (root/'integration-screenshots').mkdir(exist_ok=True)
  subprocess.run(['xcrun','simctl','io',device,'screenshot',str(root/'integration-screenshots/setup-failure.png')],check=True,timeout=20,capture_output=True)
 except Exception as screenshot_error:
  result['setupScreenshotError']=type(screenshot_error).__name__
 # Backend logs can contain synthetic tokens: only collect bounded, whitelisted diagnostics.
 try:
  import runpy
  runpy.run_path(str(pathlib.Path(__file__).with_name('backend-diagnostics.py')))['capture'](root/'integration-backend-diagnostics.json')
 except Exception as diagnostic_error:
  result['diagnosticError']=type(diagnostic_error).__name__
 raise
finally:
 if 'video' in locals():
  video.send_signal(signal.SIGINT)
  try:video.wait(timeout=30)
  except subprocess.TimeoutExpired:video.kill();video.wait(timeout=10)
 try:
  import urllib.request
  with opener.open('http://127.0.0.1:61913/proof',timeout=20) as response: receipts=json.load(response)
  assert isinstance(receipts,dict) and all(isinstance(k,str) and isinstance(v,bool) for k,v in receipts.items())
  (root/'integration-final-receipts.json').write_text(json.dumps(receipts,indent=2))
 except Exception as error: result['receiptError']=type(error).__name__
 if (root/'integration-ui.xcresult').exists():
  try:
   summary=subprocess.check_output(['xcrun','xcresulttool','get','test-results','summary','--path','build/integration-ui.xcresult'],timeout=60)
   (root/'integration-test-summary.json').write_bytes(summary)
   subprocess.run(['xcrun','xcresulttool','export','attachments','--path','build/integration-ui.xcresult','--output-path','build/integration-screenshots'],check=True,timeout=120)
  except Exception as error:
   result['evidenceError']=type(error).__name__+': '+str(error)
 # Persist failure evidence even if simulator cleanup itself stalls.
 (root/'integration-result.json').write_text(json.dumps(result,indent=2))
 try: subprocess.run(['xcrun','simctl','shutdown',device],check=False,timeout=60)
 except subprocess.TimeoutExpired:
  result['cleanupError']='Simulator shutdown timed out'
  (root/'integration-result.json').write_text(json.dumps(result,indent=2))

