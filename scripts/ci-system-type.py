import json
import os
from pathlib import Path
import re
import shutil
import subprocess
from simulator_boot import boot

base = Path('build/system-type')
product = '9be1341f3fa8b346a024fe59ecfbe4816c1c797d'
def run(command, timeout=120):
    return subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          check=True, timeout=timeout).stdout.strip()
def write(name, value):
    (base / name).write_text(json.dumps(value, indent=2, ensure_ascii=False))
def read_runtime():
    runtimes = json.loads(run(['xcrun','simctl','list','runtimes','--json']))['runtimes']
    return next((r for r in runtimes if r['identifier'] == 'com.apple.CoreSimulator.SimRuntime.iOS-26-0'
                 and r.get('isAvailable') and r['version'] == '26.0.1' and r['buildversion'] == '23A8464'), None)

runtime = read_runtime()
if runtime is None:
    run(['xcodebuild','-downloadPlatform','iOS','-architectureVariant','universal'], timeout=1400)
    runtime = read_runtime()
assert runtime is not None
cli = ['xcrun','simctl']
device = run(cli + ['create', 'PUBO System Text SE (3rd generation)',
                    'com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation',runtime['identifier']])
boot(device, base / 'boot.json')
args = ['xcodebuild','-quiet','-project','PUBO.xcodeproj','-scheme','PUBO','-configuration','Debug',
        '-destination','platform=iOS Simulator,id=' + device,'-destination-timeout','120',
        '-derivedDataPath','build/debug','-parallel-testing-enabled','NO','CODE_SIGNING_ALLOWED=NO']
subprocess.run(args + ['build-for-testing'], check=True, timeout=1500)
run(cli + ['install',device,'build/debug/Build/Products/Debug-iphonesimulator/PUBO.app'], timeout=300)
helptext = (base/'simctl-ui-help.txt').read_text()
settings = [(name, text, test) for (name,text,test) in [
    ('normal', 'large', 'testNormalSystemContentSize'),
    ('accessibility', 'accessibility-extra-large', 'testAccessibilitySystemContentSize')]]
categories = {}
data = {}
receipt = {'product':product,'control':os.environ['GITHUB_SHA'],'device':device,
           'runtime':runtime['version'],'runtimeBuild':runtime['buildversion'],'deviceType':'iPhone SE (3rd generation)',
           'categories': categories, 'observations': data}
try:
    for phase, category, test in settings:
        assert re.search(r'(?<![a-z-])' + re.escape(category) + r'(?![a-z-])', helptext, re.I), category
        result = run(cli + ['ui',device,'content_size',category])
        actual = run(cli + ['ui',device,'content_size'])
        categories[phase] = {'commandValue':category,'response':result,'readback':actual}
        write('verification.json', receipt)
        bundle = Path('build') / (phase + '-system-type.xcresult')
        code = subprocess.run(args + ['-resultBundlePath',str(bundle),
            '-only-testing:PUBOUITests/SystemTypeEvidenceTests/' + test, 'test-without-building'],timeout=700).returncode
        target = base / (phase + '-attachments')
        if bundle.exists():
            run(['xcrun','xcresulttool','export','attachments','--path',str(bundle),'--output-path',str(target)])
            summary = json.loads(run(['xcrun','xcresulttool','get','test-results','summary','--path',str(bundle)]))
            write(phase + '-summary.json', summary)
            for group in json.loads((target/'manifest.json').read_text()):
                for attach in group['attachments']:
                    label = attach['suggestedHumanReadableName']
                    source = target / attach['exportedFileName']
                    for key in ['text','actions','geometry']:
                        if label.startswith(phase + '-' + key):
                            if key == 'geometry':
                                data[phase] = json.loads(source.read_text())
                                write(phase + '-geometry.json', data[phase])
                            else:
                                shutil.copyfile(source, base/(phase + '-' + key + '.png'))
            write('verification.json', receipt)
        assert code == 0, (phase,code)
        assert summary['passedTests'] == 1 and summary['failedTests'] == 0 and summary.get('skippedTests',0) == 0
        assert phase in data, phase
    assert categories['normal']['readback'] != categories['accessibility']['readback'], categories
    normal, access = data['normal'], data['accessibility']
    assert normal['fixture'] == access['fixture'] == 'at4tltest0025'
    assert normal['deviceWidth'] == access['deviceWidth'] == 375
    assert abs(normal['bodyWidth'] - access['bodyWidth']) <= 3, (normal['bodyWidth'], access['bodyWidth'])
    receipt['bodyHeightRatio'] = access['bodyHeight'] / normal['bodyHeight']
    assert receipt['bodyHeightRatio'] > 1.15, (normal['bodyHeight'],access['bodyHeight'])
    for rendered in [normal,access]:
        assert len(rendered['actions']) == 4 and all(a['hittable'] for a in rendered['actions'])
        assert '--large-text' not in rendered['arguments']
    receipt['status'] = 'PASS'
finally:
    write('verification.json', receipt)
    subprocess.run(cli + ['shutdown',device], timeout=90, check=False)
