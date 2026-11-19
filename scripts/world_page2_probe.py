"""Single opt-in iOS Simulator observation. Does not alter the shared shard runner/gates."""
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import re
import signal
import struct
import subprocess
import uuid
import zlib

CLASS = 'WorldPageTwoPosterDiagnosticUITests'
METHOD = 'testNativeSecondPagePosterVisiblePixels'
IDENT = f'{CLASS}/{METHOD}'
SELECTOR = f'-only-testing:PUBOUITests/{IDENT}'
DEFINE = 'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) DEBUG PUBO_PAGE2_POSTER_PROBE'
TYPE = 'com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max'
RUNTIME = 'com.apple.CoreSimulator.SimRuntime.iOS-26-1'
MODEL = 'iPhone 17 Pro Max'
XCODE = 'Xcode 26.0.1\nBuild version 17A400'

def check(value, why):
    if not value:
        raise ValueError(why)

def save(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2, allow_nan=False)+'\n')

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def output(cmd, timeout=45):
    return subprocess.check_output(cmd, text=True, timeout=timeout).strip()

def build_cmd(dd):
    return ['xcodebuild','-project','PUBO.xcodeproj','-scheme','PUBO','-configuration','Debug',
            '-sdk','iphonesimulator','-destination','generic/platform=iOS Simulator','-derivedDataPath',str(dd),
            'CODE_SIGNING_ALLOWED=NO','ARCHS=x86_64','ONLY_ACTIVE_ARCH=YES',DEFINE,'build-for-testing']

def run_cmd(product, device, bundle):
    # Explicit generated .xctestrun: no project/scheme resolution, rebuild, or fallback suite.
    return ['xcodebuild','-xctestrun',str(product),'-destination','platform=iOS Simulator,id='+device,
            '-destination-timeout','90','-parallel-testing-enabled','NO','-resultBundlePath',str(bundle),
            SELECTOR,'test-without-building']

def supervised(cmd, log, seconds):
    with log.open('wb') as target:
        p = subprocess.Popen(cmd, stdout=target, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            return p.wait(timeout=seconds)
        finally:
            if p.poll() is None:
                os.killpg(p.pid, signal.SIGTERM)
                try: p.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    os.killpg(p.pid, signal.SIGKILL); p.wait(timeout=10)

def discovery(dd):
    # Generated sources list proves actual target membership after XcodeGen, independent of pbx group format.
    lists = [p for p in dd.rglob('PUBOUITests.SwiftFileList')
             if 'PUBOUITests.build' in p.parts and 'x86_64' in p.parts]
    wanted = (Path('UITests')/(CLASS+'.swift')).resolve()
    hits = [p for p in lists if any(Path(line.strip().strip('"')).resolve() == wanted for line in p.read_text().splitlines())]
    check(len(hits)==1,'Opt-in file missing/ambiguous in generated x86_64 PUBOUITests target SwiftFileList')
    products = list((dd/'Build/Products').glob('*.xctestrun'))
    check(len(products)==1,'Missing or ambiguous fresh simulator .xctestrun')
    return hits[0],products[0]

def counts(s, total=False):
    expect={'passedTests':1,'failedTests':0,'skippedTests':0,'expectedFailures':0}
    if total: expect['totalTestCount']=1
    return all(type(s.get(k)) is int and s[k]==v for k,v in expect.items())

def numeric(x):
    return type(x) in (float,int) and math.isfinite(x)

def pair(xs):
    return isinstance(xs,list) and len(xs)==2 and all(map(numeric,xs)) and 0<=xs[0]<=xs[1]

def png_size(data):
    # Keep raw screenshot identity; a header-only/truncated PNG cannot count as evidence.
    check(data.startswith(b'\x89PNG\r\n\x1a\n'),'Missing PNG')
    pos=8; dims=None; compressed=0
    while pos+12<=len(data):
        n=struct.unpack_from('>I',data,pos)[0]; tag=data[pos+4:pos+8]; stop=pos+12+n
        check(stop<=len(data),'Truncated PNG')
        content=data[pos+8:pos+8+n]
        check(zlib.crc32(tag+content)&0xffffffff==struct.unpack_from('>I',data,pos+8+n)[0],'PNG CRC mismatch')
        if dims is None:
            check(tag==b'IHDR' and n==13,'Missing IHDR');dims=struct.unpack('>II',content[:8])
        if tag==b'IDAT': compressed+=n
        if tag==b'IEND':
            check(n==0 and stop==len(data) and compressed>0 and dims[1]>dims[0]>0,'Incomplete portrait PNG')
            return list(dims)
        pos=stop
    raise ValueError('No final PNG chunk')

def verify(summary, manifest, directory, owned):
    check(counts(summary,True) and summary.get('result')=='Passed','Exactly one passed test; zero/skip/fail is not observation')
    groups=summary['devicesAndConfigurations']; check(len(groups)==1 and counts(groups[0]),'Unexpected configuration counts')
    device=groups[0]['device']
    check(device.get('deviceId')==owned and device.get('modelName')==MODEL and
          device.get('osVersion')=='26.1' and device.get('platform')=='iOS Simulator' and
          device.get('architecture')=='x86_64','Result is not from owned iOS 26.1 x86_64 Pro Max')
    check(isinstance(manifest,list) and len(manifest)==1 and manifest[0].get('testIdentifier')==IDENT+'()'
          and manifest[0].get('testIdentifierURL','').endswith('/PUBOUITests/'+IDENT),'Wrong method or target')
    items=manifest[0]['attachments']
    def one(name):
        matches=[a for a in items if a.get('suggestedHumanReadableName','').startswith(name+'_')]
        check(len(matches)==1 and matches[0].get('deviceId')==owned and
              matches[0].get('isAssociatedWithFailure') is False,'Missing/ambiguous/wrong-device attachment: '+name)
        fname=matches[0]['exportedFileName']; check(Path(fname).name==fname,'Invalid attachment filename')
        p=directory/fname; check(p.is_file() and p.stat().st_size>0,'Missing attachment payload: '+name)
        return p
    r=json.loads(one('page2-observations').read_text())
    check(r.get('result')=='OBSERVED_VISIBLE_RED_FIXTURE' and r.get('lastStage')=='observed-not-speed-certified'
          and r.get('latencyPointEstimate')=='UNAVAILABLE' and r.get('physicalDeviceProof') is False and
          r.get('measuredHitches')=='UNAVAILABLE','No valid probe receipt')
    rows=r['observations']; check(isinstance(rows,list) and 1<=len(rows)<=12,'No bounded sample series')
    last=rows[-1]
    check([x.get('index') for x in rows]==list(range(1,len(rows)+1)),'Missing/out-of-order sample')
    check(type(r.get('drags')) is int and 1<=r['drags']<=32 and r['drags']==last.get('drags')
          and last.get('preState')==last.get('postState') and last.get('postState') in ('video-frame','cached') and
          numeric(last.get('redFraction')) and .35<last['redFraction']<=1 and last.get('pixelSignatureSeen') is True,
          'Positive whole-screen raster and stable state not established')
    b=r['baselineAbsentBracketUptime']; ts=last['shotBracketUptime']
    check(pair(b) and pair(ts) and b[1]<=ts[0] and r.get('visibleAtOrBeforeUptime')==ts[1],'Invalid observation bracket')
    duration=ts[1]-b[0]; bounds=r.get('viewportToVisibleRedConservativeBoundsSeconds')
    check(pair(bounds) and bounds[0]==0 and math.isclose(bounds[1],duration,abs_tol=1e-8)
          and numeric(r.get('absentBaselineToRedUpperBoundSeconds')) and
          math.isclose(r['absentBaselineToRedUpperBoundSeconds'],duration,abs_tol=1e-8),'Invalid conservative bound')
    retained={}
    for name in ('page2-newest-target-absent','page2-eligible-'+str(last['index'])):
        p=one(name); data=p.read_bytes()
        retained[name]={'file':p.name,'sha256':sha(p),'pixels':png_size(data)}
    initial,positive=retained.values()
    check(initial['pixels']==positive['pixels'] and initial['sha256']!=positive['sha256'],'Missing distinct same-device before/after capture')
    return {'exactTest':IDENT,'device':device,'screenshots':retained,'result':'OBSERVED_VISIBLE_RED_FIXTURE',
            'scope':'Synthetic simulator observation only; not device proof, no numerical latency acceptance.'}

def main():
    from simulator_boot import boot
    out=Path('build/page2-probe-evidence'); out.mkdir(parents=True,exist_ok=False)
    dd=Path('build/page2-probe-derived').resolve()
    device=None; bundle=out/'page2.xcresult'; stack={'status':'UNAVAILABLE','physicalDeviceProof':False}
    try:
        stack.update(phase='setup',commit=output(['git','rev-parse','HEAD']),runId=os.environ['GITHUB_RUN_ID'],
                     runAttempt=os.environ['GITHUB_RUN_ATTEMPT'],configuration='Debug',condition=DEFINE,
                     selection=SELECTOR,architecture=platform.machine(),xcode=output(['xcodebuild','-version']),
                     model=MODEL,deviceType=TYPE,runtime=RUNTIME,continuousScreenRecording=False)
        check(stack['commit']==os.environ['GITHUB_SHA'] and stack['architecture']=='x86_64' and stack['xcode']==XCODE,
              'Expected exact checkout and pinned Intel Xcode 26.0.1')
        check(not dd.exists(),'DerivedData is not fresh; cannot prove binary identity')
        stack['phase']='build-for-testing'; bc=build_cmd(dd); stack['buildCommand']=bc
        check(supervised(bc,out/'build.log',1500)==0,'build-for-testing failed')
        source_list,product=discovery(dd)
        stack.update(sourceFileList=str(source_list),xctestrunName=product.name,xctestrunSHA256=sha(product))
        (out/'compiled-test-sources.txt').write_bytes(source_list.read_bytes())
        # No preexisting device can be shut down/deleted; only the newly returned UUID is owned.
        stack['phase']='create-simulator'
        raw=output(['xcrun','simctl','create','PUBO page2 '+MODEL,TYPE,RUNTIME],60)
        device=str(uuid.UUID(raw)).upper()
        inventory=json.loads(output(['xcrun','simctl','list','devices','--json']))['devices']
        selected=[v for v in inventory.get(RUNTIME,[]) if v.get('udid','').upper()==device]
        check(len(selected)==1 and selected[0].get('deviceTypeIdentifier')==TYPE,'Owned template identity mismatch')
        stack['udid']=device; stack['phase']='boot'; boot(device,out/'boot.json')
        stack['phase']='test-without-building'; rc=run_cmd(product,device,bundle); stack['runCommand']=rc
        test_status=supervised(rc,out/'test.log',1800); stack['xcodeTestExit']=test_status
        stack['phase']='read-test-evidence'
        check(bundle.is_dir(),'No xcresult produced')
        summary=json.loads(output(['xcrun','xcresulttool','get','test-results','summary','--path',str(bundle)],90))
        save(out/'summary.json',summary)
        exp=out/'attachments'
        subprocess.run(['xcrun','xcresulttool','export','attachments','--path',str(bundle),'--output-path',str(exp)],check=True,timeout=120)
        check(test_status==0,'Native XCTest was unsuccessful; see xcresult, attachments and logs')
        verified=verify(summary,json.loads((exp/'manifest.json').read_text()),exp,device)
        save(out/'verified.json',verified);stack.update(status='OBSERVED_VISIBLE_RED_FIXTURE',phase='completed')
    except Exception as e:
        stack['error']=type(e).__name__+': '+str(e); raise
    finally:
        save(out/'identity-and-stage.json',stack)
        if device:
            for verb in ('shutdown','delete'):
                try: subprocess.run(['xcrun','simctl',verb,device],check=False,timeout=60)
                except (OSError,subprocess.TimeoutExpired): pass

if __name__=='__main__': main()
