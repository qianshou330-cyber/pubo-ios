"""Run only isolated UI scenarios; never authenticate against production."""
import json
import re
import os
import pathlib
import platform
import signal
import subprocess
import time
from simulator_boot import boot
from ui_selection import FOCUSED, selection, complete
from refresh_lifecycle import complete_lifecycle

root = pathlib.Path('build')
root.mkdir(exist_ok=True)
devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '--json']))['devices']
iphones = [dict(d, runtime=runtime) for runtime, values in devices.items() if '.iOS-26-' in runtime for d in values if d['name'].startswith('iPhone')]
if not iphones:
    raise SystemExit('No available iPhone simulator runtime')
small = next((d for d in iphones if 'SE' in d['name']), next((d for d in iphones if 'Max' not in d['name'] and 'Plus' not in d['name']), iphones[0]))
large = next((d for d in iphones if 'Max' in d['name']), iphones[-1])
selected = list({d['udid']: d for d in [small, large]}.values())
if len(selected) < 2:
    raise SystemExit('Two different iPhone sizes are required')
if os.environ.get('PUBO_SIM_SIZE') in ('small', 'large'):
    selected = [selected[0 if os.environ['PUBO_SIM_SIZE'] == 'small' else -1]]
focused = os.environ.get('PUBO_REGRESSION_147_ONLY') == '1'
if focused and any(os.environ.get(key) == '1' for key in (
    'PUBO_SOCIAL_ALIGNMENT', 'PUBO_AUTH_VIDEO', 'PUBO_HOME_MOTION', 'PUBO_AUTH_APPEARANCE')):
    raise SystemExit('Focused regression cannot be combined with other suites')
shard = os.environ.get("PUBO_UI_SHARD", "")
if shard and (focused or any(os.environ.get(key) == "1" for key in ("PUBO_SOCIAL_ALIGNMENT", "PUBO_AUTH_VIDEO", "PUBO_HOME_MOTION", "PUBO_AUTH_APPEARANCE"))):
    raise SystemExit("UI shard cannot combine with another selection")
shard_selection = selection(shard) if shard else None
private_back_probe = shard in ('private-back-without-picker', 'private-back-after-picker')
if private_back_probe and (os.environ.get('PUBO_SIM_SIZE') != 'large' or 'Max' not in selected[0]['name']):
    raise SystemExit('Private Back comparison requires the iPhone Max iOS 26 simulator')
room_back_probe = shard in ('room-back-without-picker', 'room-back-after-picker')
if room_back_probe and (os.environ.get('PUBO_SIM_SIZE') != 'small' or 'SE' not in selected[0]['name']):
    raise SystemExit('Room Back comparison requires the iPhone SE iOS 26 simulator')
world_scroll_probe = shard in ('world-scroll-cross-page', 'world-scroll-signposts')
if world_scroll_probe and (os.environ.get('PUBO_SIM_SIZE') not in ('small', 'large') or
                           ('SE' if os.environ['PUBO_SIM_SIZE'] == 'small' else 'Max') not in selected[0]['name']):
    raise SystemExit('World scroll comparison requires explicit SE or Max iOS 26 simulator')
created = []
environment = []
def diagnostic(command, timeout):
    try:
        subprocess.run(command, timeout=timeout)
    except (subprocess.TimeoutExpired, OSError) as error:
        print('Diagnostic unavailable: ' + str(error), flush=True)

for index, template in enumerate(selected):
    # GitHub's pre-created device reached Booted while testmanagerd was not ready.
    # Use fresh, task-owned devices and wait for the complete boot sequence.
    identifier = subprocess.check_output(['xcrun', 'simctl', 'create', 'PUBO ' + template['name'],
                                         template['deviceTypeIdentifier'], template['runtime']], text=True, timeout=60).strip()
    inventory = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', '--json']))['devices']
    device = next(dict(d, runtime=runtime) for runtime, values in inventory.items() for d in values if d['udid'] == identifier)
    created.append(device)
    (root / 'simulators.json').write_text(json.dumps(created, indent=2))
    record = {'device': device['name'], 'runtime': device['runtime'], 'udid': identifier, 'boot': 'PENDING', 'tests': 'NOT_RUN',
              'commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True, timeout=15).strip(),
              'hostArchitecture': platform.machine(),
              'xcode': subprocess.check_output(['xcodebuild', '-version'], text=True, timeout=30).strip()}
    environment.append(record)
    bundle = root / f'ui-{index}.xcresult'
    screenshots = root / 'screenshots' / str(index)
    screenshots.mkdir(parents=True, exist_ok=True)
    test_exit = 1
    process = None
    back_video = None
    try:
        print('Booting fresh simulator: ' + device['name'], flush=True)
        boot(identifier, root / f'boot-{index}.json')
        record['boot'] = 'READY'
        if os.environ.get('PUBO_SOCIAL_ALIGNMENT') == '1':
            social_bundle = root / f'social-{index}.xcresult'
            video = subprocess.Popen(['xcrun', 'simctl', 'io', identifier, 'recordVideo', '--codec=h264', str(screenshots / 'social-interactions.mp4')])
            try:
                social = subprocess.run(['xcodebuild', '-project', 'PUBO.xcodeproj', '-scheme', 'PUBO', '-configuration', 'Debug',
                    '-destination', f'platform=iOS Simulator,id={identifier}', '-destination-timeout', '90',
                    '-derivedDataPath', 'build/debug', '-resultBundlePath', str(social_bundle), '-parallel-testing-enabled', 'NO',
                    '-only-testing:PUBOUITests/SocialAlignmentUITests', '-only-testing:PUBOUITests/ParityBatchUITests', '-only-testing:PUBOUITests/AccountSettingsParityUITests', '-only-testing:PUBOUITests/ProfileParityUITests', '-only-testing:PUBOUITests/DriveParityUITests', '-only-testing:PUBOUITests/ChannelParityUITests', '-only-testing:PUBOUITests/FollowRequestParityUITests', '-only-testing:PUBOUITests/FollowListParityUITests', '-only-testing:PUBOUITests/ContactPagingParityUITests', '-only-testing:PUBOUITests/LocalTimelineUITests/testOlderFailureRetriesAtReadingPositionWithoutDroppingPosts', 'CODE_SIGNING_ALLOWED=NO', 'test'], timeout=2700)
                record['socialTests'] = 'PASS' if social.returncode == 0 else 'FAIL'
            finally:
                video.send_signal(signal.SIGINT)
                try: video.wait(timeout=30)
                except subprocess.TimeoutExpired: video.kill(); video.wait(timeout=10)
                if social_bundle.exists():
                    diagnostic(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(social_bundle), '--output-path', str(screenshots / 'social')], 90)
                    result = subprocess.run(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(social_bundle)], capture_output=True, text=True, timeout=60)
                    if result.returncode == 0: (root / f'social-{index}-summary.json').write_text(result.stdout)
            if social.returncode: raise RuntimeError('Social interaction tests failed')
        if os.environ.get('PUBO_AUTH_VIDEO') == '1':
            motion_bundle = root / f'video-{index}.xcresult'
            video = subprocess.Popen(['xcrun', 'simctl', 'io', identifier, 'recordVideo', '--codec=h264', str(screenshots / 'auth-video-interactions.mp4')])
            try:
                motion = subprocess.run(['xcodebuild', '-project', 'PUBO.xcodeproj', '-scheme', 'PUBO', '-configuration', 'Debug',
                    '-destination', f'platform=iOS Simulator,id={identifier}', '-destination-timeout', '90',
                    '-derivedDataPath', 'build/debug', '-resultBundlePath', str(motion_bundle), '-parallel-testing-enabled', 'NO',
                    '-only-testing:PUBOUITests/AuthStaticUITests', 'CODE_SIGNING_ALLOWED=NO', 'test'], timeout=720)
                record['videoTests'] = 'PASS' if motion.returncode == 0 else 'FAIL'
            finally:
                video.send_signal(signal.SIGINT)
                try: video.wait(timeout=30)
                except subprocess.TimeoutExpired: video.kill(); video.wait(timeout=10)
                if motion_bundle.exists():
                    diagnostic(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(motion_bundle), '--output-path', str(screenshots / 'video')], 90)
                    result = subprocess.run(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(motion_bundle)], capture_output=True, text=True, timeout=60)
                    if result.returncode == 0: (root / f'video-{index}-summary.json').write_text(result.stdout)
            if motion.returncode: raise RuntimeError('Login video tests failed')
        if os.environ.get('PUBO_HOME_MOTION') == '1':
            motion_bundle = root / f'motion-{index}.xcresult'
            video = subprocess.Popen(['xcrun', 'simctl', 'io', identifier, 'recordVideo', '--codec=h264', str(screenshots / 'home-chart-announcement.mp4')])
            try:
                motion = subprocess.run(['xcodebuild', '-project', 'PUBO.xcodeproj', '-scheme', 'PUBO', '-configuration', 'Debug',
                    '-destination', f'platform=iOS Simulator,id={identifier}', '-destination-timeout', '90',
                    '-derivedDataPath', 'build/debug', '-resultBundlePath', str(motion_bundle), '-parallel-testing-enabled', 'NO',
                    '-only-testing:PUBOUITests/HomeMotionUITests', 'CODE_SIGNING_ALLOWED=NO', 'test'], timeout=720)
                record['motionTests'] = 'PASS' if motion.returncode == 0 else 'FAIL'
            finally:
                video.send_signal(signal.SIGINT)
                try: video.wait(timeout=30)
                except subprocess.TimeoutExpired: video.kill(); video.wait(timeout=10)
                if motion_bundle.exists():
                    diagnostic(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(motion_bundle), '--output-path', str(screenshots / 'motion')], 90)
                    result = subprocess.run(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(motion_bundle)], capture_output=True, text=True, timeout=60)
                    if result.returncode == 0: (root / f'motion-{index}-summary.json').write_text(result.stdout)
            if motion.returncode: raise RuntimeError('Home motion or click-target tests failed')
            if os.environ.get('PUBO_MOTION_ONLY') == '1':
                test_exit = 0
                record['tests'] = 'FOCUSED_ONLY'
                continue
        print('Simulator boot complete; starting isolated UI tests', flush=True)
        command = ['xcodebuild', '-project', 'PUBO.xcodeproj', '-scheme', 'PUBO', '-configuration', 'Debug',
                   '-destination', f'platform=iOS Simulator,id={identifier}', '-destination-timeout', '90',
                   '-derivedDataPath', 'build/debug', '-resultBundlePath', str(bundle),
                   '-parallel-testing-enabled', 'NO', '-only-testing:PUBOUITests/PUBOUITests', 'CODE_SIGNING_ALLOWED=NO', 'test']
        if focused:
            command.remove('-only-testing:PUBOUITests/PUBOUITests')
            command[-1:-1] = ['-only-testing:PUBOUITests/' + name for name in FOCUSED]
            record['selection'] = 'regression-147-five-tests'
        if shard_selection:
            expected, selectors = shard_selection
            command.remove('-only-testing:PUBOUITests/PUBOUITests')
            command[-1:-1] = selectors
            record['selection'] = shard
            record['expectedTests'] = expected
        if os.environ.get('PUBO_AUTH_APPEARANCE') == '1':
            command.remove('-only-testing:PUBOUITests/PUBOUITests')
            command[-1:-1] = ['-only-testing:PUBOUITests/PUBOUITests/' + name for name in [
                'testWelcomeRegistrationSheetCanCloseAndLogin',
                'testLargeTextRegistrationKeepsFieldsAndCodeButtonReachable',
                'testPasswordVisibilityAndAccountChangePreserveSafety',
                'testNativeLoginAndFourTabs']]
        if os.environ.get('PUBO_PREBUILT_TESTS') == '1':
            if command[-1] != 'test': raise RuntimeError('Unexpected test action')
            command[-1] = 'test-without-building'
        if private_back_probe or room_back_probe:
            back_video = subprocess.Popen(['xcrun', 'simctl', 'io', identifier, 'recordVideo', '--codec=h264',
                                           str(screenshots / ('room-native-back.mp4' if room_back_probe else 'private-native-back.mp4'))])
        if world_scroll_probe:
            back_video = subprocess.Popen(['xcrun', 'simctl', 'io', identifier, 'recordVideo', '--codec=h264',
                                           str(screenshots / 'world-scroll.mp4')])
        process = subprocess.Popen(command, start_new_session=True)
        started = time.monotonic()
        while process.poll() is None:
            try:
                process.wait(timeout=30)
            except subprocess.TimeoutExpired:
                elapsed = round(time.monotonic() - started)
                print(f'UI runner {index}: {elapsed}s elapsed; waiting for actual test result', flush=True)
                if elapsed >= 1800:
                    record['tests'] = 'TIMEOUT'
                    raise TimeoutError('UI runner exceeded 30 minutes')
        test_exit = process.returncode
        if (focused or shard_selection) and test_exit == 0:
            gate_result = subprocess.run(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary',
                '--path', str(bundle)], capture_output=True, text=True, timeout=60, check=True)
            gate = json.loads(gate_result.stdout)
            (root / f'ui-{index}-summary.json').write_text(gate_result.stdout)
            expected = len(FOCUSED) if focused else shard_selection[0]
            if not complete(gate, expected):
                test_exit = 1
                record['gateError'] = f'Exactly {expected} passing tests, zero failures/skips/expected failures required'
        record['tests'] = 'PASS' if test_exit == 0 else 'FAIL'
        if test_exit == 0 and os.environ.get('PUBO_AUTH_APPEARANCE') == '1':
            subprocess.run(['xcrun', 'simctl', 'launch', '--terminate-running-process', identifier,
                            'com.bolubo.native', '--ui-testing', '--logged-out', '--system-appearance'], check=True, timeout=45)
            video = subprocess.Popen(['xcrun', 'simctl', 'io', identifier, 'recordVideo', '--codec=h264', str(screenshots / 'brand-theme-switch.mp4')])
            try:
                for theme in ['light', 'dark', 'light']:
                    subprocess.run(['xcrun', 'simctl', 'ui', identifier, 'appearance', theme], check=True, timeout=20)
                    time.sleep(3)
                    subprocess.run(['xcrun', 'simctl', 'io', identifier, 'screenshot', str(screenshots / ('brand-' + theme + '.png'))], check=True, timeout=30)
            finally:
                video.send_signal(signal.SIGINT)
                try: video.wait(timeout=30)
                except subprocess.TimeoutExpired: video.kill(); video.wait(timeout=10)
        if test_exit == 0 and index == 0 and not focused and not private_back_probe and not room_back_probe and not world_scroll_probe:
            # A real simulator recording of synthetic loading, not a rendered mockup.
            video = subprocess.Popen(['xcrun', 'simctl', 'io', identifier, 'recordVideo', '--codec=h264',
                                      str(screenshots / 'loading-skeleton.mp4')])
            try:
                subprocess.run(['xcrun', 'simctl', 'launch', '--terminate-running-process', identifier,
                                'com.bolubo.native', '--ui-testing', '--slow-startup', '--skeleton-loading',
                                '--fixture-tab-avatar'], check=True, timeout=45)
                time.sleep(6)
                subprocess.run(['xcrun', 'simctl', 'io', identifier, 'screenshot',
                                str(screenshots / 'loading-skeleton-live.png')], check=True, timeout=30)
                time.sleep(9)
            finally:
                video.send_signal(signal.SIGINT)
                try: video.wait(timeout=30)
                except subprocess.TimeoutExpired: video.kill(); video.wait(timeout=10)
    except BaseException as error:
        record['error'] = type(error).__name__ + ': ' + str(error)
        raise
    finally:
        if process is not None and process.poll() is None:
            os.killpg(process.pid, signal.SIGINT)
            try: process.wait(timeout=20)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL); process.wait(timeout=10)
        if back_video is not None and back_video.poll() is None:
            back_video.send_signal(signal.SIGINT)
            try: back_video.wait(timeout=30)
            except subprocess.TimeoutExpired: back_video.kill(); back_video.wait(timeout=10)
        if bundle.exists():
            try:
                result = subprocess.run(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(bundle)],
                                        capture_output=True, text=True, timeout=60)
                if result.returncode == 0:
                    summary = json.loads(result.stdout)
                    (root / f'ui-{index}-summary.json').write_text(json.dumps(summary, indent=2))
            except (subprocess.TimeoutExpired, OSError, ValueError) as error:
                print('Result summary unavailable: ' + str(error), flush=True)
            diagnostic(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(bundle),
                        '--output-path', str(screenshots)], timeout=90)
        if test_exit:
            diagnostic(['xcrun', 'simctl', 'io', identifier, 'screenshot',
                        str(screenshots / 'runner-failure.png')], timeout=30)
        if world_scroll_probe:
            # Raw XCTest bundle owns metrics. No absent metric becomes a zero/pass.
            scope = {'status': 'NOT_EVALUATED', 'physicalDevice': False,
                     'smoothnessAcceptance': 'NOT_EVALUATED', 'shard': shard,
                     'metricEvidence': 'Inspect raw xcresult; missing/nonfinite/empty samples are UNAVAILABLE',
                     'recordingOverhead': 'simctl video active; simulator/host and recording affect performance'}
            (root / f'world-scroll-measurement-scope-{index}.json').write_text(json.dumps(scope, indent=2))
        if shard == 'chat-presentation-composer' or private_back_probe:
            navigation_capture = {'status': 'UNAVAILABLE', 'interpretation': 'Passive counts/lifecycle only; not native Back touch, complete navigation stack, or acceptance proof'}
            try:
                navigation_logs = subprocess.run(['xcrun', 'simctl', 'spawn', identifier, 'log', 'show',
                    '--style', 'json', '--last', '1h', '--predicate',
                    'subsystem == "com.pubo.chatnavigation.diagnostics"'], capture_output=True, text=True, timeout=60)
                (root / f'chatnavigation-diagnostics-{index}.json').write_text(navigation_logs.stdout)
                navigation_capture['exitCode'] = navigation_logs.returncode
                navigation_capture['status'] = 'CAPTURED' if navigation_logs.returncode == 0 and 'event=privateTaskEntered' in navigation_logs.stdout else 'INCOMPLETE'
            except (subprocess.TimeoutExpired, OSError) as error:
                navigation_capture['error'] = type(error).__name__
            (root / f'chatnavigation-capture-{index}.json').write_text(json.dumps(navigation_capture, indent=2))
        if room_back_probe:
            room_capture = {'status': 'UNAVAILABLE', 'roomLifecycleVerified': False,
                            'interpretation': 'Synthetic room control: existing lease/path/keyboard counts only; no room lifecycle or delivered touch-duration proof'}
            try:
                room_logs = subprocess.run(['xcrun', 'simctl', 'spawn', identifier, 'log', 'show',
                    '--style', 'json', '--last', '1h', '--predicate',
                    'subsystem == "com.pubo.chatnavigation.diagnostics"'], capture_output=True, text=True, timeout=60)
                (root / f'room-back-navigation-diagnostics-{index}.json').write_text(room_logs.stdout)
                room_capture['exitCode'] = room_logs.returncode
                room_capture['status'] = 'CAPTURED_COUNTS' if room_logs.returncode == 0 and 'event=leasesChanged' in room_logs.stdout else 'INCOMPLETE'
            except (subprocess.TimeoutExpired, OSError) as error:
                room_capture['error'] = type(error).__name__
            (root / f'room-back-navigation-capture-{index}.json').write_text(json.dumps(room_capture, indent=2))
        if shard == 'chat-presentation-states':
            # Observe synthetic load stages without changing test results or timeouts.
            capture = {'status': 'UNAVAILABLE', 'interpretation': 'Diagnostics only; absent stages are not proof of success'}
            try:
                logs = subprocess.run(['xcrun', 'simctl', 'spawn', identifier, 'log', 'show',
                    '--style', 'json', '--last', '30m', '--predicate',
                    'subsystem == "com.pubo.chatload.diagnostics"'], capture_output=True, text=True, timeout=60)
                (root / f'chatload-diagnostics-{index}.json').write_text(logs.stdout)
                capture['exitCode'] = logs.returncode
                capture['status'] = 'CAPTURED' if logs.returncode == 0 and 'load-start' in logs.stdout else 'INCOMPLETE'
            except (subprocess.TimeoutExpired, OSError) as error:
                capture['error'] = type(error).__name__
            (root / f'chatload-capture-{index}.json').write_text(json.dumps(capture, indent=2))
        if shard == 'chat-presentation-states':
            startup_capture = {'status': 'UNAVAILABLE', 'interpretation': 'Main scheduling and bar layout only; never AX/hittability or acceptance proof'}
            try:
                startup_logs = subprocess.run(['xcrun', 'simctl', 'spawn', identifier, 'log', 'show',
                    '--style', 'json', '--last', '1h', '--predicate',
                    'subsystem == "com.pubo.startup.diagnostics"'], capture_output=True, text=True, timeout=60)
                (root / f'startup-diagnostics-{index}.json').write_text(startup_logs.stdout)
                startup_capture['exitCode'] = startup_logs.returncode
                startup_capture['status'] = 'CAPTURED' if startup_logs.returncode == 0 and 'event=pulseStart' in startup_logs.stdout else 'INCOMPLETE'
            except (subprocess.TimeoutExpired, OSError) as error:
                startup_capture['error'] = type(error).__name__
            (root / f'startup-capture-{index}.json').write_text(json.dumps(startup_capture, indent=2))
        if shard in ('chat-presentation-states', 'video-poster'):
            hit_capture = {'status': 'UNAVAILABLE', 'interpretation': 'Synthetic bar-center UIKit hit observations, not AX readiness or acceptance'}
            try:
                hit_logs = subprocess.run(['xcrun', 'simctl', 'spawn', identifier, 'log', 'show',
                    '--style', 'json', '--last', '1h', '--predicate',
                    'subsystem == "com.pubo.tabhit.diagnostics"'], capture_output=True, text=True, timeout=60)
                (root / f'tabhit-diagnostics-{index}.json').write_text(hit_logs.stdout)
                hit_capture['exitCode'] = hit_logs.returncode
                hit_capture['status'] = 'CAPTURED' if hit_logs.returncode == 0 and 'event=sample' in hit_logs.stdout else 'INCOMPLETE'
            except (subprocess.TimeoutExpired, OSError) as error:
                hit_capture['error'] = type(error).__name__
            (root / f'tabhit-capture-{index}.json').write_text(json.dumps(hit_capture, indent=2))
        if shard == 'chat-alignment-actions':
            report_capture = {'status': 'UNAVAILABLE', 'interpretation': 'Action/state lifecycle only; no visual proof or gate override'}
            try:
                report_logs = subprocess.run(['xcrun', 'simctl', 'spawn', identifier, 'log', 'show',
                    '--style', 'json', '--last', '1h', '--predicate',
                    'subsystem == "com.pubo.roomreport.diagnostics"'], capture_output=True, text=True, timeout=60)
                (root / f'roomreport-diagnostics-{index}.json').write_text(report_logs.stdout)
                report_capture['exitCode'] = report_logs.returncode
                report_capture['status'] = 'CAPTURED' if report_logs.returncode == 0 and 'event=actionEntered' in report_logs.stdout else 'INCOMPLETE'
            except (subprocess.TimeoutExpired, OSError) as error:
                report_capture['error'] = type(error).__name__
            (root / f'roomreport-capture-{index}.json').write_text(json.dumps(report_capture, indent=2))
        if shard == 'video-poster':
            # Diagnostic collection cannot turn a failed test into a pass.
            capture = {'status': 'UNAVAILABLE'}
            try:
                logs = subprocess.run(['xcrun', 'simctl', 'spawn', identifier, 'log', 'show',
                    '--style', 'json', '--last', '30m', '--predicate',
                    'subsystem == "com.pubo.media.diagnostics"'], capture_output=True, text=True, timeout=60)
                (root / f'media-diagnostics-{index}.json').write_text(logs.stdout)
                capture['exitCode'] = logs.returncode
                capture['status'] = 'CAPTURED' if logs.returncode == 0 else 'INCOMPLETE'
                capture['interpretation'] = 'Stage logs are diagnostics, not visual or performance proof'
            except (subprocess.TimeoutExpired, OSError) as error:
                capture['error'] = type(error).__name__
            (root / f'media-capture-{index}.json').write_text(json.dumps(capture, indent=2))
        if focused:
            capture = {'status': 'UNAVAILABLE', 'captureStarted': False}
            try:
                logs = subprocess.run(['xcrun', 'simctl', 'spawn', identifier, 'log', 'show',
                    '--style', 'json', '--last', '30m', '--predicate',
                    'subsystem == "com.pubo.refresh.diagnostics"'], capture_output=True, text=True, timeout=60)
                (root / f'refresh-diagnostics-{index}.json').write_text(logs.stdout)
                capture['exitCode'] = logs.returncode
                capture['captureStarted'] = bool(re.search(r'captureStarted=[1-9][0-9]*', logs.stdout))
                capture['status'] = 'CAPTURED' if logs.returncode == 0 and capture['captureStarted'] else 'INCOMPLETE'
                capture['interpretation'] = 'No callback inference permitted without captureStarted marker'
                capture['lifecycleVerified'] = logs.returncode == 0 and complete_lifecycle(logs.stdout)
            except (subprocess.TimeoutExpired, OSError) as error:
                capture['error'] = type(error).__name__
            (root / f'refresh-capture-{index}.json').write_text(json.dumps(capture, indent=2))
            if test_exit == 0 and not capture.get('lifecycleVerified', False):
                print('Refresh lifecycle proof missing: require same-process background, resume and third applied generation', flush=True)
                test_exit = 1
                record['tests'] = 'FAIL'
                record['gateError'] = 'Strict same-process post-resume application evidence missing'
        if focused or shard_selection:
            try:
                privacy_logs = subprocess.run(['xcrun', 'simctl', 'spawn', identifier, 'log', 'show',
                    '--style', 'json', '--last', '30m', '--predicate',
                    'subsystem == "com.pubo.privacy.diagnostics"'], capture_output=True, text=True, timeout=60)
                (root / f'privacy-diagnostics-{index}.json').write_text(privacy_logs.stdout)
            except (subprocess.TimeoutExpired, OSError) as error:
                print('Privacy diagnostic unavailable: ' + type(error).__name__, flush=True)
        diagnostic(['xcrun', 'simctl', 'shutdown', identifier], timeout=60)
        (root / 'test-environment.json').write_text(json.dumps(environment, indent=2))
    if test_exit: raise SystemExit(test_exit)
