import json,os,pathlib,subprocess,sys
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
from simulator_boot import boot
root=pathlib.Path('build');root.mkdir(exist_ok=True)
inventory=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','--json']))['devices']
devices=[dict(d,runtime=r) for r,values in inventory.items() if '.iOS-26-' in r for d in values if d['name'].startswith('iPhone')]
template=next((d for d in devices if 'SE' in d['name']),devices[0])
device=subprocess.check_output(['xcrun','simctl','create','PUBO real backend',template['deviceTypeIdentifier'],template['runtime']],text=True).strip()
result={'status':'RUNNING','device':template['name'],'runtime':template['runtime'],'productionAPIRequests':0,'transport':'loopback-only real backend'}
try:
 boot(device,root/'integration-boot.json')
 command=['xcodebuild','-project','PUBO.xcodeproj','-scheme','PUBO','-configuration','Debug','-destination','platform=iOS Simulator,id='+device,'-derivedDataPath','build/integration-derived','-resultBundlePath','build/integration-ui.xcresult','-parallel-testing-enabled','NO','-only-testing:PUBOUITests/PUBOIntegrationTests','CODE_SIGNING_ALLOWED=NO','test']
 subprocess.run(command,check=True,timeout=1200,env={**os.environ,'TEST_RUNNER_PUBO_REQUIRE_ISOLATED_BACKEND':'1'})
 summary=json.loads(subprocess.check_output(['xcrun','xcresulttool','get','test-results','summary','--path','build/integration-ui.xcresult']))
 (root/'integration-test-summary.json').write_text(json.dumps(summary,indent=2))
 assert summary.get('passedTests',0)==14 and summary.get('failedTests',0)==0 and summary.get('skippedTests',0)==0, 'All fourteen real-backend UI tests must actually run'
 result['status']='PASS'
except Exception as error:
 result['status']='FAIL';result['error']=type(error).__name__+': '+str(error)
 raise
finally:
 if (root/'integration-ui.xcresult').exists():
  try:
   summary=subprocess.check_output(['xcrun','xcresulttool','get','test-results','summary','--path','build/integration-ui.xcresult'],timeout=60)
   (root/'integration-test-summary.json').write_bytes(summary)
   subprocess.run(['xcrun','xcresulttool','export','attachments','--path','build/integration-ui.xcresult','--output-path','build/integration-screenshots'],check=True,timeout=120)
  except Exception as error:
   result['evidenceError']=type(error).__name__+': '+str(error)
 subprocess.run(['xcrun','simctl','shutdown',device],check=False,timeout=60)
 (root/'integration-result.json').write_text(json.dumps(result,indent=2))

