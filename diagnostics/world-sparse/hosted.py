"""Read-only hosted adapter: validate provenance, then interpret the existing manual runner outputs."""
import hashlib
import json
import os
import platform
import subprocess
import sys
from pathlib import Path

BASE = 'c8227e6bceb62129c018b9b3f70f5c9324a01782'
VARIANT = '151d642df874307ebeffee7d0f325bb5ab9d5046d5d17ce4bd768a260dd11a0a'
REPO = 'qianshou330-cyber/pubo-ios'
REF = 'refs/heads/ui-four-tabs-148-20261112'
MARK = '[world-sparse-probe]'
METHOD = '-only-testing:PUBOUITests/SparseWorldUITests/testActiveWorldRowCaptureAfterRealDrags'
PIN = {
    'README.md':'926c6e97950d75d9a9075a48d47d89f585a22baa739c19313ffa4132a4977aea',
    'SparseProbe.swift.inc':'b9b559218ee22b111de5bf13783e5ff8273c5c3ac84b061c5168b05955a759ca',
    'SparseWorldUITests.swift.inc':'1440def330a02bc116b77e8c7f67fa2797f7d5cdb11b582794972af7b6422ea3',
    'materialize.py':'bd62d0a11492123ead516f9531bfecf71d72e676183065869d00044f03995791',
    'run.py':'4d327e8a175e2e068f100a88bcf1dc82862ce909d300ec3cafbd0b1b78420621',
    'test_sparse.py':'090a9e45c1a05be0910384e39db21c3beddfb0d97a4e1f2f405b6bffbf2e3d3b',
    'verify.py':'94841055e724d13e441df6c3696330e8a1e49251398d86500978c254eafc9a8b',
}

def check(ok, msg):
    if not ok:
        raise ValueError(msg)

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def git(repo, *args):
    return subprocess.check_output(['git','-C',str(repo),*args],text=True,timeout=90).strip()

def prove_archive(repo, head, base=BASE):
    check(git(repo,'rev-parse','--is-shallow-repository') == 'false','Incomplete history')
    check(git(repo,'rev-parse','HEAD') == head and git(repo,'rev-parse','--verify',base+'^{commit}') == base,
          'Wrong checkout or missing pinned commit')
    git(repo,'merge-base','--is-ancestor',base,head)
    tree=git(repo,'rev-parse','--verify',base+'^{tree}')
    check(MARK in git(repo,'show','-s','--format=%B',head),'Exact case-sensitive head marker absent')
    return tree

def preflight(root):
    env=os.environ
    check(env['GITHUB_ACTIONS']=='true' and env['RUNNER_ENVIRONMENT']=='github-hosted' and env['GITHUB_JOB']=='diagnostic-world-sparse' and
          env['GITHUB_REPOSITORY']==REPO and env['GITHUB_REF']==REF and env['GITHUB_EVENT_NAME']=='push' and
          platform.system()=='Darwin' and platform.machine()=='x86_64','Not the permitted disposable hosted Intel job')
    source=Path(__file__).resolve().parent
    actual={name:sha(source/name) for name in PIN}
    check(actual==PIN,'Manual diagnostic changed, review/re-pin before use')
    tree=prove_archive(Path(env['GITHUB_WORKSPACE']),env['GITHUB_SHA'])
    context={'workflowHead':env['GITHUB_SHA'],'sourceArchive':BASE,'sourceTree':tree,'manualFiles':actual,
             'targetVariantDiffSHA256':VARIANT,'job':env['GITHUB_JOB'],'run':env['GITHUB_RUN_ID'],
             'attempt':env['GITHUB_RUN_ATTEMPT'],'repo':REPO,'ref':REF,'host':platform.platform(),
             'physicalDeviceProof':False,'productBinary':False}
    (root/'preflight.json').write_text(json.dumps(context,indent=2)+'\n')

def classify(root):
    """Only a validating manual verdict can finish the job. Preserve the initial UNAVAILABLE on all other exits."""
    n=root/'native'
    rc=int((root/'native-exit.txt').read_text())
    i=json.loads((n/'identity.json').read_text())
    check(rc in (0,3) and i.get('phase')=='finished' and i.get('xcodeTestExit')==0,'Native or evidence-validation failure')
    check(i.get('base')==BASE and i.get('variantDiffSHA256')==VARIANT==sha(n/'variant.diff') and
          i.get('productBuild') is False and i.get('hardwareIPhone') is False,'Wrong instrumented source')
    check(i.get('model')=='iPhone 17 Pro Max' and i.get('runtime')=='com.apple.CoreSimulator.SimRuntime.iOS-26-1' and
          i.get('xcode')=='Xcode 26.0.1\nBuild version 17A400' and
          [s for s in i['testCommand'] if s.startswith('-only-testing')]==[METHOD],'Wrong native target')
    o=json.loads((n/'observation.json').read_text())
    # The pinned driver checks native target, one passed test, attachments and PNGs. Reuse
    # its raw app/gesture verifier here; copied or contradictory summary strings cannot pass.
    from verify import verify
    exp=n/'attachments'
    m=json.loads((exp/'manifest.json').read_text())
    ident=METHOD.partition(':PUBOUITests/')[2]
    check(len(m)==1 and m[0]['testIdentifier']==ident+'()' and
          m[0]['testIdentifierURL'].endswith('/PUBOUITests/'+ident),'Wrong exported native method')
    def attachment(name):
        rows=[a for a in m[0]['attachments'] if a['suggestedHumanReadableName'].startswith(name+'_')]
        check(len(rows)==1 and rows[0]['deviceId']==i['simulator'] and rows[0].get('isAssociatedWithFailure') is False,
              'Missing, wrong-device or failure attachment '+name)
        filename=rows[0]['exportedFileName']
        check(filename and Path(filename).name==filename,'Invalid exported name')
        return exp/filename
    check(o==verify(json.loads((n/'app-receipt.json').read_text()),json.loads(attachment('sparse-gestures').read_text())),
          'Raw app/gesture evidence differs from reported observation')
    check(all(sha(attachment('sparse-'+tag))==i['screens'][tag] for tag in ['before','after']) and
          i['screens']['before']!=i['screens']['after'],'Missing or inconsistent native screenshot evidence')
    hits=o.get('observedChangesInBinaryBranch')
    check(isinstance(hits,list) and all(type(k) is int and k>0 for k in hits),'Invalid hit evidence')
    status='EXERCISED_SYNTHETIC' if hits else 'UNEXERCISED'
    check(i.get('status')==o.get('status')==status and (rc==0)==bool(hits),'Conflicting status, exit or observed changes')
    return status

def main(mode, root):
    if mode=='preflight':
        preflight(root)
    elif mode=='classify':
        try:
            status=classify(root)
        except (OSError,ValueError,KeyError,TypeError) as e:
            status='UNAVAILABLE'
            print(f'Incomplete/inconsistent evidence: {type(e).__name__}: {e}')
        (root/'status.txt').write_text(status+'\n')
        print(status)
    else:
        raise ValueError('Unknown hosted operation')

if __name__=='__main__':
    main(sys.argv[1],Path(sys.argv[2]))
