"""Run only isolated UI scenarios; never authenticate against production."""
import json
import pathlib
import subprocess

root = pathlib.Path('build')
root.mkdir(exist_ok=True)
devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '--json']))['devices']
iphones = [d for runtime, values in devices.items() if '.iOS-' in runtime for d in values if d['name'].startswith('iPhone')]
if not iphones:
    raise SystemExit('No available iPhone simulator runtime')
small = next((d for d in iphones if 'SE' in d['name']), next((d for d in iphones if 'Max' not in d['name'] and 'Plus' not in d['name']), iphones[0]))
large = next((d for d in iphones if 'Max' in d['name']), iphones[-1])
selected = list({d['udid']: d for d in [small, large]}.values())
if len(selected) < 2:
    raise SystemExit('Two different iPhone sizes are required')
(root / 'simulators.json').write_text(json.dumps(selected, indent=2))
for index, device in enumerate(selected):
    result = subprocess.run(['xcodebuild', '-project', 'PUBO.xcodeproj', '-scheme', 'PUBO', '-configuration', 'Debug', '-destination', f"platform=iOS Simulator,id={device['udid']}", '-derivedDataPath', 'build/debug', '-resultBundlePath', f'build/ui-{index}.xcresult', 'CODE_SIGNING_ALLOWED=NO', 'test'])
    bundle = root / f'ui-{index}.xcresult'
    if bundle.exists():
        screenshots = root / 'screenshots' / str(index)
        screenshots.mkdir(parents=True, exist_ok=True)
        subprocess.run(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(bundle), '--output-path', str(screenshots)])
    if result.returncode: raise SystemExit(result.returncode)
