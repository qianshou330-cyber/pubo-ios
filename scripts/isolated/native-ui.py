import json,os,pathlib,subprocess,sys,signal,time
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
from simulator_boot import boot
root=pathlib.Path('build');root.mkdir(exist_ok=True)
inventory=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','--json']))['devices']
runtime='com.apple.CoreSimulator.SimRuntime.iOS-26-0'
assert runtime in inventory, 'The baseline iOS 26.0 runtime is required; do not silently use another runtime'
devices=[dict(d,runtime=runtime) for d in inventory[runtime] if d['name'].startswith('iPhone')]
template=next(d for d in devices if d['name']=='iPhone 17 Pro Max')
device=subprocess.check_output(['xcrun','simctl','create','PUBO real backend',template['deviceTypeIdentifier'],template['runtime']],text=True).strip()
result={'status':'RUNNING','device':template['name'],'runtime':template['runtime'],'productionAPIRequests':0,'transport':'loopback-only real backend'}
try:
 boot(device,root/'integration-boot.json')
 command=['xcodebuild','-quiet','-project','PUBO.xcodeproj','-scheme','PUBO','-configuration','Debug','-destination','platform=iOS Simulator,id='+device,'-derivedDataPath','build/integration-derived','-resultBundlePath','build/integration-ui.xcresult','-parallel-testing-enabled','NO','-only-testing:PUBOUITests/PUBOIntegrationTests','-only-testing:PUBOUITests/ReconnectionUITests','CODE_SIGNING_ALLOWED=NO','test']
 (root/'integration-screenshots').mkdir(exist_ok=True)
 recording={'startedAt':time.time(),'file':'integration-screenshots/interactions.mp4'}
 (root/'integration-recording.json').write_text(json.dumps(recording))
 video=subprocess.Popen(['xcrun','simctl','io',device,'recordVideo','--codec=h264',str(root/'integration-screenshots/interactions.mp4')])
 subprocess.run(command,check=True,timeout=1500,env={**os.environ,'TEST_RUNNER_PUBO_REQUIRE_ISOLATED_BACKEND':'1'})
 summary=json.loads(subprocess.check_output(['xcrun','xcresulttool','get','test-results','summary','--path','build/integration-ui.xcresult']))
 (root/'integration-test-summary.json').write_text(json.dumps(summary,indent=2))
 assert summary.get('passedTests',0)==21 and summary.get('failedTests',0)==0 and summary.get('skippedTests',0)==0, 'All twenty-one real-backend UI tests must actually run'
 result['status']='PASS'
except Exception as error:
 result['status']='FAIL';result['error']=type(error).__name__+': '+str(error)
 raise
finally:
 if 'video' in locals():
  video.send_signal(signal.SIGINT)
  try:video.wait(timeout=30)
  except subprocess.TimeoutExpired:video.kill();video.wait(timeout=10)
 try:
  import urllib.request
  with urllib.request.urlopen('http://127.0.0.1:61913/proof',timeout=20) as response: receipts=json.load(response)
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
 subprocess.run(['xcrun','simctl','shutdown',device],check=False,timeout=60)
 (root/'integration-result.json').write_text(json.dumps(result,indent=2))

