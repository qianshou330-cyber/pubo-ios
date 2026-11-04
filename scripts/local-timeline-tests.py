"""Task-owned simulators; synthetic protected GIF responses, never production writes."""
import json,os,pathlib,signal,subprocess,time
from simulator_boot import boot
from simulator_resources import SimulatorResources
root=pathlib.Path('build');root.mkdir(exist_ok=True)
inventory=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','--json']))['devices']
runtime='com.apple.CoreSimulator.SimRuntime.iOS-26-0'
assert runtime in inventory, 'The baseline iOS 26.0 runtime is required; do not silently use another runtime'
phones=[dict(d,runtime=runtime) for d in inventory[runtime] if d['name'].startswith('iPhone')]
small=os.environ.get('PUBO_SIM_SIZE')=='small'
device=next(d for d in phones if ('SE' in d['name'] if small else d['name']=='iPhone 17 Pro Max'))
owned=root/'timeline-owned-device.json'
if owned.exists():
    saved=json.loads(owned.read_text())
    assert saved['name']=='PUBO Local '+device['name'] and saved['runtime']==device['runtime']
    current=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','--json']))['devices']
    assert any(d['udid']==saved['udid'] and d['name']==saved['name'] for values in current.values() for d in values), 'Only reuse the simulator created by this job'
    identifier=saved['udid']
else:
    identifier=subprocess.check_output(['xcrun','simctl','create','PUBO Local '+device['name'],device['deviceTypeIdentifier'],device['runtime']],text=True,timeout=60).strip()
    owned.write_text(json.dumps({'udid':identifier,'name':'PUBO Local '+device['name'],'runtime':device['runtime']}))
record={'device':device['name'],'udid':identifier,'tests':'PENDING','productionRequests':0};(root/'timeline-environment.json').write_text(json.dumps(record))
regressions=['testHistoricalReferenceAndReturnToLatest','testChatEditRecallAndReactions','testChatEditConflictAndLostResponseKeepDraftUntilManualResolution','testLargeTextChatKeepsInputAndActionsReachable','testMultipleAccountsSwitchAndPreserveOtherAccount','testLostChatReplyReconcilesWithoutNewMessage','testSecondChatShowsReplyRequired','testNativeLoginAndFourTabs']
groups=[('timeline-preview',['-only-testing:PUBOUITests/LocalTimelineUITests/testFirstLocalAndFourTabsInBothThemes']),('timeline',['-only-testing:PUBOUITests/LocalTimelineUITests','-skip-testing:PUBOUITests/LocalTimelineUITests/testFirstLocalAndFourTabsInBothThemes']),('home',['-only-testing:PUBOUITests/HomeMotionUITests']),('gif',['-only-testing:PUBOUITests/PrivateGIFUITests']),('favorites',['-only-testing:PUBOUITests/PersonalGIFUITests']),('social',['-only-testing:PUBOUITests/SocialAlignmentUITests']),('regression',['-only-testing:PUBOUITests/PUBOUITests/'+n for n in regressions])]
groups += [('auth-preview',['-only-testing:PUBOUITests/AuthStaticUITests/testStaticWelcomeAndCenteredLoginBothThemes','-only-testing:PUBOUITests/AuthStaticUITests/testTotpBackupAndAccountChange','-only-testing:PUBOUITests/AuthStaticUITests/testRegistrationRulesFormAndResetBothThemes']),('auth-functional',['-only-testing:PUBOUITests/AuthStaticUITests','-skip-testing:PUBOUITests/AuthStaticUITests/testStaticWelcomeAndCenteredLoginBothThemes','-skip-testing:PUBOUITests/AuthStaticUITests/testTotpBackupAndAccountChange','-skip-testing:PUBOUITests/AuthStaticUITests/testRegistrationRulesFormAndResetBothThemes'])]
groups = [(name, tests + (['-only-testing:PUBOUITests/PUBOUITests/testPasswordVisibilityAndAccountChangePreserveSafety', '-only-testing:PUBOUITests/PUBOUITests/testLargeTextRegistrationKeepsFieldsAndCodeButtonReachable'] if name == 'auth-functional' else [])) for name, tests in groups]
groups += [('chat',['-only-testing:PUBOUITests/ChatAlignmentUITests'])]
selected=os.environ.get('PUBO_UI_GROUPS')
if selected: groups=[item for item in groups if item[0] in selected.split(',')]
try:
    boot(identifier,root/('timeline-boot-'+os.environ.get('PUBO_UI_SCOPE','all')+'.json'))
    # Settle first-launch simulator services before XCTest requests its background
    # assertion. This is a separate, recorded fixture-only launch, not a test retry.
    subprocess.run(['xcrun','simctl','install',identifier,'build/debug/Build/Products/Debug-iphonesimulator/PUBO.app'],check=True,timeout=90)
    try:
        subprocess.run(['xcrun','simctl','launch',identifier,'com.bolubo.native','--ui-testing','--timeline-align','--gif-preview'],check=True,timeout=60)
        record['warmupLaunch']='LAUNCHED'
    except (subprocess.TimeoutExpired, subprocess.CalledProcessError) as error:
        record['warmupLaunch']='FAILED: '+type(error).__name__
        print('Warmup launch unavailable; actual XCTest launch and assertions are still required.',flush=True)
    time.sleep(12)
    try:
        subprocess.run(['xcrun','simctl','io',identifier,'screenshot',str(root/('warmup-'+os.environ.get('PUBO_UI_SCOPE','all')+'.png'))],check=True,timeout=60)
        record['warmupScreenshot']='CAPTURED'
    except (subprocess.TimeoutExpired, subprocess.CalledProcessError) as error:
        # Warmup diagnostics are separate from actual UI assertions and recordings.
        # A slow simctl screenshot must not prevent XCTest from measuring the app.
        record['warmupScreenshot']='FAILED: '+type(error).__name__
        print('Warmup screenshot unavailable; real UI tests still required.',flush=True)
    try:
        cleanup=subprocess.run(['xcrun','simctl','terminate',identifier,'com.bolubo.native'],check=False,timeout=30)
        record['warmupCleanup']='TERMINATED' if cleanup.returncode==0 else 'XCTEST_WILL_RELAUNCH'
    except subprocess.TimeoutExpired:
        record['warmupCleanup']='XCTEST_WILL_RELAUNCH_AFTER_CLEANUP_TIMEOUT'
    time.sleep(3)
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'],'a') as output:output.write('simulator_ready=true\n')
    for name,selection in groups:
        shots=root/'screenshots'/name;shots.mkdir(parents=True,exist_ok=True)
        bundle=root/(name+'.xcresult')
        recording={'startedAt':time.time(),'file':str(shots/'interactions.mp4')}
        video=subprocess.Popen(['xcrun','simctl','io',identifier,'recordVideo','--codec=h264',str(shots/'interactions.mp4')])
        try:
            with SimulatorResources(root/(name+'-resources.json')):
                result=subprocess.run(['xcodebuild','-quiet','-project','PUBO.xcodeproj','-scheme','PUBO','-configuration','Debug','-destination',f'platform=iOS Simulator,id={identifier}','-destination-timeout','90','-derivedDataPath','build/debug','-resultBundlePath',str(bundle),'-parallel-testing-enabled','NO']+selection+['CODE_SIGNING_ALLOWED=NO','test'],timeout=1600 if name in ('auth-functional', 'chat') else 1100)
        finally:
            video.send_signal(signal.SIGINT)
            try:video.wait(timeout=30)
            except subprocess.TimeoutExpired:video.kill();video.wait(timeout=10)
            recording['finishedAt']=time.time()
            (root/(name+'-recording.json')).write_text(json.dumps(recording,indent=2))
            if bundle.exists():
                subprocess.run(['xcrun','xcresulttool','export','attachments','--path',str(bundle),'--output-path',str(shots)],timeout=90,check=True)
                summary=subprocess.check_output(['xcrun','xcresulttool','get','test-results','summary','--path',str(bundle)],text=True,timeout=60)
                (root/(name+'-summary.json')).write_text(summary)
        record[name]='PASS' if result.returncode==0 else 'FAIL'
        # Continue independent regression groups so failures do not hide unrelated evidence.
    if any(record.get(name) != 'PASS' for name,_ in groups):raise RuntimeError('One or more UI groups failed; see individual summaries')
    record['tests']='PASS'
except Exception as error:
    record['tests']='FAIL'
    record['error']=type(error).__name__+': '+str(error)
    raise
finally:
    (root/('timeline-environment-'+os.environ.get('PUBO_UI_SCOPE','all')+'.json')).write_text(json.dumps(record,indent=2))
    subprocess.run(['xcrun','simctl','shutdown',identifier],timeout=60)
