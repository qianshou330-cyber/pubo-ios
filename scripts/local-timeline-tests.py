"""Task-owned simulators; synthetic protected GIF responses, never production writes."""
import json,os,pathlib,signal,subprocess
from simulator_boot import boot
from simulator_resources import SimulatorResources
root=pathlib.Path('build');root.mkdir(exist_ok=True)
inventory=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','--json']))['devices']
phones=[dict(d,runtime=r) for r,values in inventory.items() if '.iOS-26-' in r for d in values if d['name'].startswith('iPhone')]
small=os.environ.get('PUBO_SIM_SIZE')=='small'
device=next(d for d in phones if ('SE' in d['name'] if small else d['name']=='iPhone 17 Pro Max'))
identifier=subprocess.check_output(['xcrun','simctl','create','PUBO Local '+device['name'],device['deviceTypeIdentifier'],device['runtime']],text=True,timeout=60).strip()
record={'device':device['name'],'udid':identifier,'tests':'PENDING','productionRequests':0};(root/'timeline-environment.json').write_text(json.dumps(record))
regressions=['testHistoricalReferenceAndReturnToLatest','testChatEditRecallAndReactions','testChatEditConflictAndLostResponseKeepDraftUntilManualResolution','testLargeTextChatKeepsInputAndActionsReachable','testMultipleAccountsSwitchAndPreserveOtherAccount','testLostChatReplyReconcilesWithoutNewMessage','testSecondChatShowsReplyRequired','testNativeLoginAndFourTabs']
groups=[('timeline-preview',['-only-testing:PUBOUITests/LocalTimelineUITests/testFirstLocalAndFourTabsInBothThemes']),('timeline',['-only-testing:PUBOUITests/LocalTimelineUITests','-skip-testing:PUBOUITests/LocalTimelineUITests/testFirstLocalAndFourTabsInBothThemes']),('home',['-only-testing:PUBOUITests/HomeMotionUITests']),('gif',['-only-testing:PUBOUITests/PrivateGIFUITests']),('favorites',['-only-testing:PUBOUITests/PersonalGIFUITests']),('social',['-only-testing:PUBOUITests/SocialAlignmentUITests']),('regression',['-only-testing:PUBOUITests/PUBOUITests/'+n for n in regressions])]
selected=os.environ.get('PUBO_UI_GROUPS')
if selected: groups=[item for item in groups if item[0] in selected.split(',')]
try:
    boot(identifier,root/'gif-boot.json')
    for name,selection in groups:
        shots=root/'screenshots'/name;shots.mkdir(parents=True,exist_ok=True)
        bundle=root/(name+'.xcresult')
        video=subprocess.Popen(['xcrun','simctl','io',identifier,'recordVideo','--codec=h264',str(shots/'interactions.mp4')])
        try:
            with SimulatorResources(root/(name+'-resources.json')):
                result=subprocess.run(['xcodebuild','-quiet','-project','PUBO.xcodeproj','-scheme','PUBO','-configuration','Debug','-destination',f'platform=iOS Simulator,id={identifier}','-destination-timeout','90','-derivedDataPath','build/debug','-resultBundlePath',str(bundle),'-parallel-testing-enabled','NO']+selection+['CODE_SIGNING_ALLOWED=NO','test'],timeout=1100)
        finally:
            video.send_signal(signal.SIGINT)
            try:video.wait(timeout=30)
            except subprocess.TimeoutExpired:video.kill();video.wait(timeout=10)
            if bundle.exists():
                subprocess.run(['xcrun','xcresulttool','export','attachments','--path',str(bundle),'--output-path',str(shots)],timeout=90,check=True)
                summary=subprocess.check_output(['xcrun','xcresulttool','get','test-results','summary','--path',str(bundle)],text=True,timeout=60)
                (root/(name+'-summary.json')).write_text(summary)
        record[name]='PASS' if result.returncode==0 else 'FAIL'
        # Continue independent regression groups so failures do not hide unrelated evidence.
    if any(record.get(name) != 'PASS' for name,_ in groups):raise RuntimeError('One or more UI groups failed; see individual summaries')
    record['tests']='PASS'
finally:
    (root/('timeline-environment-'+os.environ.get('PUBO_UI_SCOPE','all')+'.json')).write_text(json.dumps(record,indent=2))
    subprocess.run(['xcrun','simctl','shutdown',identifier],timeout=60)
