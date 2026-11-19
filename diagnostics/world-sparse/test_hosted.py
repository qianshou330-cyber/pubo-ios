"""Offline hosted contracts. Synthetic JSON is never a native pass."""
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import hosted as h
import materialize as mat
from test_sparse import fixtures
from verify import verify

HERE=Path(__file__).resolve().parent
BASELINE=Path(os.environ.get('SPARSE_BASELINE',HERE.parents[1]))

def write(path, value):
    path.write_text(json.dumps(value))

class Hosted(unittest.TestCase):
    def test_manual_runner_unchanged_and_original_workflow_is_byte_prefix(self):
        self.assertEqual({f:h.sha(HERE/f) for f in h.PIN},h.PIN)
        workflow=(HERE.parents[1]/'.github/workflows/four-tabs.yml').read_bytes()
        old,tail=workflow.split(b'  diagnostic-world-sparse:\n')
        self.assertEqual(mat.gitblob(old),'547e96a454fd6fb5181faff074e781f206023c63')
        for required in [h.REF,h.REPO,h.MARK,"github.event_name == 'push'",'runs-on: macos-15-intel',
                         'ref: ${{ github.sha }}','fetch-depth: 0','persist-credentials: false',
                         'path: ${{ runner.temp }}/pubo-sparse-host/','if: always()','exit 3','exit 1']:
            self.assertIn(required.encode(),tail)
        self.assertEqual(tail.count(b'actions/upload-artifact'),1)
        self.assertEqual(tail.count(b'diagnostics/world-sparse/run.py --repo'),1)
        for prohibited in [b'needs:',b'continue-on-error:',b'workflow_dispatch',b'simctl',b'killall',b'sudo ',b'xcodegen generate']:
            self.assertNotIn(prohibited,tail)

    def test_runner_lists_one_created_simulator_and_only_owned_cleanup(self):
        run=(HERE/'run.py').read_text()
        self.assertIn("udid=str(uuid.UUID(common.output(['xcrun','simctl','create',",run)
        self.assertIn("for op in ['shutdown','delete']:",run)
        self.assertIn("['xcrun','simctl',op,udid]",run)
        self.assertIn("boot(udid,out/'boot.json')",run)
        boot=(BASELINE/'scripts/simulator_boot.py').read_text()
        self.assertIn("for attempt in range(2)",boot)
        self.assertIn("if os.environ.get('GITHUB_ACTIONS') == 'true':",boot)
        self.assertNotIn('delete',boot)

    def test_self_hosted_wrong_branch_and_nonpush_refused_before_git(self):
        e={'GITHUB_ACTIONS':'true','RUNNER_ENVIRONMENT':'github-hosted','GITHUB_REPOSITORY':h.REPO,
           'GITHUB_REF':h.REF,'GITHUB_EVENT_NAME':'push','GITHUB_JOB':'diagnostic-world-sparse'}
        for wrong in [{'RUNNER_ENVIRONMENT':'self-hosted'},{'GITHUB_REF':'refs/heads/main'},
                      {'GITHUB_EVENT_NAME':'pull_request'},{'GITHUB_REPOSITORY':'fork/other'},
                      {'GITHUB_JOB':'other'}]:
            with patch.dict(os.environ,e|wrong,clear=True),patch.object(h,'prove_archive') as proof:
                with self.assertRaises(ValueError):h.preflight(Path('.'))
                proof.assert_not_called()

    def test_full_history_archive_ancestry_and_exact_head_marker(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)
            def git(*a, stdin=None):
                return subprocess.check_output(['git','-C',d,'-c','user.name=fixture','-c','user.email=fixture@example.invalid',*a],
                                               text=True,input=stdin).strip()
            git('init','-q')
            tree=git('mktree',stdin='')
            base=git('commit-tree',tree,'-m','immutable synthetic base')
            head=git('commit-tree',tree,'-p',base,'-m',h.MARK)
            git('update-ref','HEAD',head)
            self.assertEqual(h.prove_archive(p,head,base),tree)
            self.assertGreater(len(subprocess.check_output(['git','-C',d,'archive',base])),0)
            with self.assertRaises(ValueError):h.prove_archive(p,base,base)
            orphan=git('commit-tree',tree,'-m','unrelated')
            with self.assertRaises(subprocess.CalledProcessError):h.prove_archive(p,head,orphan)
            wrong=git('commit-tree',tree,'-p',base,'-m',h.MARK.upper())
            git('update-ref','HEAD',wrong)
            with self.assertRaises(ValueError):h.prove_archive(p,wrong,base)
            (p/'.git/shallow').write_text(base+'\n')
            with self.assertRaises(ValueError):h.prove_archive(p,wrong,base)

class Verdict(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)
            for f in mat.REL:
                (p/f).parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(BASELINE/f,p/f)
            (p/'UITests').mkdir()
            _,cls.diff=mat.write_variant(p)

    def example(self,p,*,nohit=False):
        n=p/'native';exp=n/'attachments';exp.mkdir(parents=True)
        r,g=fixtures()
        if nohit:r['events']=[]
        o=verify(r,g);write(n/'app-receipt.json',r);write(n/'observation.json',o)
        write(exp/'t.json',g);(exp/'a.png').write_bytes(b'synthetic-before');(exp/'b.png').write_bytes(b'synthetic-after')
        filelist=[('sparse-gestures','t.json'),('sparse-before','a.png'),('sparse-after','b.png')]
        method=h.METHOD.split(':PUBOUITests/')[1]
        write(exp/'manifest.json',[{'testIdentifier':method+'()','testIdentifierURL':'x://unit/PUBOUITests/'+method,
                                    'attachments':[{'exportedFileName':file,'suggestedHumanReadableName':label+'_test',
                                    'deviceId':'fixture','isAssociatedWithFailure':False} for label,file in filelist]}])
        (n/'variant.diff').write_text(self.diff);(p/'native-exit.txt').write_text('3' if nohit else '0')
        i={'phase':'finished','xcodeTestExit':0,'base':h.BASE,'variantDiffSHA256':h.VARIANT,'productBuild':False,
           'hardwareIPhone':False,'model':'iPhone 17 Pro Max','runtime':'com.apple.CoreSimulator.SimRuntime.iOS-26-1',
           'simulator':'fixture','xcode':'Xcode 26.0.1\nBuild version 17A400','testCommand':[h.METHOD],
           'status':o['status'],'screens':dict(before=h.sha(exp/'a.png'),after=h.sha(exp/'b.png'))}
        write(n/'identity.json',i)
        return n,exp,i,r,o

    def test_true_hit_and_valid_non_green_nohit_after_pinned_driver(self):
        for nohit,status in [(False,'EXERCISED_SYNTHETIC'),(True,'UNEXERCISED')]:
            with tempfile.TemporaryDirectory() as d:
                root=Path(d);self.example(root,nohit=nohit)
                self.assertEqual(h.classify(root),status)
                (root/'native-exit.txt').write_text('0' if nohit else '3')
                with self.assertRaises(ValueError):h.classify(root)

    def test_missing_corrupt_or_contradictory_evidence_never_becomes_hit_or_nohit(self):
        for reason in ['startup','exit','sources','manifest','receipt','wrong-nested','screenshot','invented-hit','selector']:
            with self.subTest(reason=reason),tempfile.TemporaryDirectory() as d:
                p=Path(d);n,exp,i,r,o=self.example(p)
                if reason=='startup':i['phase']='boot';write(n/'identity.json',i)
                if reason=='exit':(p/'native-exit.txt').write_text('1')
                if reason=='sources':(n/'variant.diff').write_text('other tree')
                if reason=='manifest':(exp/'manifest.json').unlink()
                if reason=='receipt':(n/'app-receipt.json').unlink()
                if reason=='wrong-nested':r['events'][1]['stored'].remove('w80-leaf');write(n/'app-receipt.json',r)
                if reason=='screenshot':(exp/'b.png').write_bytes(b'other')
                if reason=='invented-hit':o['observedChangesInBinaryBranch']=[20];write(n/'observation.json',o)
                if reason=='selector':i['testCommand'].append('-only-testing:another');write(n/'identity.json',i)
                h.main('classify',p)
                self.assertEqual((p/'status.txt').read_text(),'UNAVAILABLE\n')
