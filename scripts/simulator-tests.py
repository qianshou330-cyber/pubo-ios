"""Run only isolated UI scenarios; never authenticate against production."""
import json
import os
import pathlib
import signal
import subprocess
import time

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
        subprocess.run(['xcrun', 'simctl', 'boot', identifier], check=True, timeout=60)
        subprocess.run(['xcrun', 'simctl', 'bootstatus', identifier, '-b'], check=True, timeout=300)
        record['boot'] = 'READY'
        print('Simulator boot complete; starting isolated UI tests', flush=True)
        command = ['xcodebuild', '-project', 'PUBO.xcodeproj', '-scheme', 'PUBO', '-configuration', 'Debug',
                   '-destination', f'platform=iOS Simulator,id={identifier}', '-destination-timeout', '90',
                   '-derivedDataPath', 'build/debug', '-resultBundlePath', str(bundle),
                   '-parallel-testing-enabled', 'NO', 'CODE_SIGNING_ALLOWED=NO', 'test']
        process = subprocess.Popen(command, start_new_session=True)
        started = time.monotonic()
        while process.poll() is None:
            try:
                process.wait(timeout=30)
            except subprocess.TimeoutExpired:
                elapsed = round(time.monotonic() - started)
                print(f'UI runner {index}: {elapsed}s elapsed; waiting for actual test result', flush=True)
                if elapsed >= 1200:
                    record['tests'] = 'TIMEOUT'
                    raise TimeoutError('UI runner exceeded 20 minutes')
        test_exit = process.returncode
        record['tests'] = 'PASS' if test_exit == 0 else 'FAIL'
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
            diagnostic(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(bundle),
                        '--output-path', str(screenshots)], timeout=90)
        if test_exit:
            diagnostic(['xcrun', 'simctl', 'io', identifier, 'screenshot',
                        str(screenshots / 'runner-failure.png')], timeout=30)
        diagnostic(['xcrun', 'simctl', 'shutdown', identifier], timeout=60)
        (root / 'test-environment.json').write_text(json.dumps(environment, indent=2))
    if test_exit: raise SystemExit(test_exit)
