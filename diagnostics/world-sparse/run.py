"""Opt in locally on a pinned dedicated Mac. Never installs/signs/transfers to a physical device."""
import argparse,contextlib,hashlib,json,os,platform,subprocess,shutil,tempfile,sys,uuid
from pathlib import Path
import materialize as mat
from verify import verify,check

CLASS='SparseWorldUITests'; METHOD='testActiveWorldRowCaptureAfterRealDrags'; IDENT=f'{CLASS}/{METHOD}'
COND='SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) DEBUG PUBO_SPARSE_WORLD_PROBE'
def main(repo,out):
    if platform.system()!='Darwin' or platform.machine()!='x86_64':raise ValueError('Requires dedicated Intel Mac with Xcode 26.0.1')
    if os.environ.get('GITHUB_ACTIONS')=='true' and os.environ.get('RUNNER_ENVIRONMENT')!='github-hosted':
        raise ValueError('Refuse CI-only simulator service recovery on a self-hosted Mac')
    # Refuse to overwrite existing evidence or materialize inside the user checkout.
    repo=repo.resolve();out=out.resolve(); check(repo!=out and repo not in out.parents,'Choose a fresh evidence directory outside repository')
    out.mkdir(parents=True,exist_ok=False)
    manifest={'base':mat.BASE,'status':'UNAVAILABLE','productBuild':False,'hardwareIPhone':False}
    try:
        with tempfile.TemporaryDirectory(prefix='pubo-sparse-') as d:
            src=Path(d)/'src';mat.archive(repo,src)
            files,diff=mat.write_variant(src)
            b=diff.encode();(out/'variant.diff').write_bytes(b)
            manifest.update(files=files,variantDiffSHA256=hashlib.sha256(b).hexdigest(),phase='brand/project')
            # Tool and boot logic read from this immutable archive. Native execution never touches repo.
            sys.path.insert(0,str(src/'scripts'));import world_page2_probe as common
            from simulator_boot import boot
            with contextlib.chdir(src):
                check(common.output(['xcodebuild','-version'])==common.XCODE,'Wrong Xcode version')
                for args in [['swift','scripts/brand-assets.swift'],['xcodegen','generate']]:
                    subprocess.run(args,timeout=300,check=True)
                dd=Path(d)/'derived'
                build=common.build_cmd(dd);build[build.index(common.DEFINE)]=COND;manifest.update(phase='build',buildCommand=build)
                check(common.supervised(build,out/'build.log',1500)==0,'Native compilation failure')
                lists=[p for p in dd.rglob('PUBOUITests.SwiftFileList') if 'x86_64' in p.parts and 'PUBOUITests.build' in p.parts
                       and str((src/'UITests'/f'{CLASS}.swift').resolve()) in [line.strip().strip('"') for line in p.read_text().splitlines()]]
                xs=list((dd/'Build/Products').glob('*.xctestrun'))
                check(len(lists)==len(xs)==1,'Missing/ambiguous test-source list or .xctestrun');manifest['xctestrunSHA256']=common.sha(xs[0])
                manifest['phase']='create-simulator'
                udid=str(uuid.UUID(common.output(['xcrun','simctl','create','PUBO Sparse '+common.MODEL,common.TYPE,common.RUNTIME],60))).upper()
                try:
                    manifest.update(simulator=udid,xcode=common.XCODE,model=common.MODEL,runtime=common.RUNTIME,phase='boot')
                    boot(udid,out/'boot.json');bundle=out/'sparse.xcresult'
                    run=common.run_cmd(xs[0],udid,bundle);run[run.index(common.SELECTOR)]='-only-testing:PUBOUITests/'+IDENT
                    manifest.update(phase='test',testCommand=run)
                    rc=common.supervised(run,out/'native.log',1200)
                    manifest.update(xcodeTestExit=rc,phase='collect')
                    base=['xcrun','xcresulttool'];summary=json.loads(common.output(base+['get','test-results','summary','--path',str(bundle)],90))
                    common.save(out/'summary.json',summary); exp=out/'attachments'
                    subprocess.run(base+['export','attachments','--path',str(bundle),'--output-path',str(exp)],check=True,timeout=120)
                    # Capture the sole bounded diagnostic file even if UI fails; never copy unrelated files from app container.
                    dat=Path(common.output(['xcrun','simctl','get_app_container',udid,'com.bolubo.native','data'],45))
                    receipts=list((dat/'tmp').glob('pubo-sparse-*.json'))
                    if len(receipts)==1 and receipts[0].stat().st_size<=2_000_000:shutil.copyfile(receipts[0],out/'app-receipt.json')
                    check(rc==0 and common.counts(summary,True) and summary.get('result')=='Passed','Require exactly one native method, no skips/failures')
                    ds=summary['devicesAndConfigurations']
                    check(len(ds)==1 and common.counts(ds[0]) and all(ds[0]['device'].get(k)==v for k,v in {
                        'deviceId':udid,'modelName':common.MODEL,'osVersion':'26.1','platform':'iOS Simulator','architecture':'x86_64'}.items()),
                        'Wrong simulator result identity')
                    man=json.loads((exp/'manifest.json').read_text())
                    check(len(man)==1 and man[0]['testIdentifier']==IDENT+'()' and
                          man[0]['testIdentifierURL'].endswith('/PUBOUITests/'+IDENT),'Wrong class/method')
                    def get(name):
                        matches=[a for a in man[0]['attachments'] if a['suggestedHumanReadableName'].startswith(name+'_')]
                        check(len(matches)==1 and matches[0]['deviceId']==udid and matches[0].get('isAssociatedWithFailure') is False,'Missing/wrong attachment '+name)
                        f=matches[0]['exportedFileName'];check(f==Path(f).name,'Malformed attachment filename');return exp/f
                    before,after=get('sparse-before'),get('sparse-after')
                    check(common.png_size(before.read_bytes())==common.png_size(after.read_bytes()) and common.sha(before)!=common.sha(after),'Missing distinct native captures')
                    manifest['screens']={'before':common.sha(before),'after':common.sha(after)}
                    g=json.loads(get('sparse-gestures').read_text());r=json.loads((out/'app-receipt.json').read_text())
                    result=verify(r,g);common.save(out/'observation.json',result)
                    manifest.update(phase='finished',status=result['status']);return 0 if result['status']=='EXERCISED_SYNTHETIC' else 3
                finally:
                    for op in ['shutdown','delete']:
                        try:subprocess.run(['xcrun','simctl',op,udid],timeout=60,check=False)
                        except (OSError,subprocess.TimeoutExpired):pass
    except Exception as e:
        manifest['error']=type(e).__name__+': '+str(e);raise
    finally:(out/'identity.json').write_text(json.dumps(manifest,indent=2)+'\n')

if __name__=='__main__':
    arg=argparse.ArgumentParser();arg.add_argument('--repo',type=Path,required=True);arg.add_argument('--out',type=Path,required=True)
    a=arg.parse_args();sys.exit(main(a.repo,a.out))
