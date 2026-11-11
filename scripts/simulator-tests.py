"""Run only isolated UI scenarios; never authenticate against production."""
import json
import os
import pathlib
import signal
import subprocess
import time
from simulator_boot import boot

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
    record = {'device': device['name'], 'udid': identifier, 'boot': 'PENDING', 'tests': 'NOT_RUN'}
    environment.append(record)
    bundle = root / f'ui-{index}.xcresult'
    screenshots = root / 'screenshots' / str(index)
    screenshots.mkdir(parents=True, exist_ok=True)
    test_exit = 1
    process = None
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
                    '-only-testing:PUBOUITests/SocialAlignmentUITests', '-only-testing:PUBOUITests/ParityBatchUITests', '-only-testing:PUBOUITests/AccountSettingsParityUITests', '-only-testing:PUBOUITests/ProfileParityUITests', '-only-testing:PUBOUITests/DriveParityUITests', '-only-testing:PUBOUITests/ChannelParityUITests', '-only-testing:PUBOUITests/LocalTimelineUITests/testOlderFailureRetriesAtReadingPositionWithoutDroppingPosts', 'CODE_SIGNING_ALLOWED=NO', 'test'], timeout=2100)
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
        if os.environ.get('PUBO_AUTH_APPEARANCE') == '1':
            command.remove('-only-testing:PUBOUITests/PUBOUITests')
            command[-1:-1] = ['-only-testing:PUBOUITests/PUBOUITests/' + name for name in [
                'testWelcomeRegistrationSheetCanCloseAndLogin',
                'testLargeTextRegistrationKeepsFieldsAndCodeButtonReachable',
                'testPasswordVisibilityAndAccountChangePreserveSafety',
                'testNativeLoginAndFourTabs']]
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
        if test_exit == 0 and index == 0:
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
        diagnostic(['xcrun', 'simctl', 'shutdown', identifier], timeout=60)
        (root / 'test-environment.json').write_text(json.dumps(environment, indent=2))
    if test_exit: raise SystemExit(test_exit)
