"""Read-only hosted adapter: validate provenance, then interpret the existing manual runner outputs."""
import hashlib
import json
import os
import platform
import subprocess
import sys
from pathlib import Path

BASE = 'c8227e6bceb62129c018b9b3f70f5c9324a01782'
VARIANT = '9dd758c0e0b906ab972a4152fa3477c772723511c5cc1ddfbe8381fc81be14f6'
REPO = 'qianshou330-cyber/pubo-ios'
REF = 'refs/heads/ui-four-tabs-148-20261112'
MARK = '[world-sparse-probe]'
METHOD = '-only-testing:PUBOUITests/SparseWorldUITests/testActiveWorldRowCaptureAfterRealDrags'
PIN = {
    'README.md':'2d459831e65760a45993fc5a7ead55d407113bdc21996175d0a7280a37b6f262',
    'SparseProbe.swift.inc':'4abef3ec66de7490b2d992328f85d0b4c2a47dee883c4ebbde6bf32c895319db',
    'SparseWorldUITests.swift.inc':'196a90900877d13ed98647fff3e701102feee62c449f1f46a477d6e200ee868b',
    'materialize.py':'bd62d0a11492123ead516f9531bfecf71d72e676183065869d00044f03995791',
    'run.py':'e851035e164cc71a681fd9ee70c9a074ace7999797673ebb7d98ab18ef319f92',
    'test_sparse.py':'1e63a3634813443b6dbd265f6793e505c8a7b4989f69101bb23ee75614aad896',
    'verify.py':'00d3c781418d0ae254598c45bf5819d9bd55562f08c08af74d2fea3477cd9e8a',
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
