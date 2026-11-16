import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from simulator_boot import boot

class RecoveryTests(unittest.TestCase):
    def exercise(self, responses, ci=True):
        with tempfile.TemporaryDirectory() as d:
            receipt = Path(d) / 'boot.json'
            with patch.dict(os.environ, {'GITHUB_ACTIONS': 'true' if ci else 'false'}), patch('simulator_boot.subprocess.run', side_effect=responses) as run:
                error = None
                try:
                    boot('task-owned', receipt)
                except Exception as exc:
                    error = exc
            return json.loads(receipt.read_text()), run.call_args_list, error

    def timeout(self):
        return subprocess.TimeoutExpired('test', 60)

    def test_success_has_no_reset(self):
        r, calls, error = self.exercise([None, None])
        self.assertIsNone(error)
        self.assertEqual(len(calls), 2)
        self.assertEqual(r['attempts'], [{'attempt': 1, 'status': 'READY'}])

    def test_shutdown_timeout_reaches_existing_reset_and_second_boot(self):
        r, calls, error = self.exercise([None, self.timeout(), self.timeout(), None, None, None])
        self.assertIsNone(error)
        self.assertEqual([c.args[0][0] for c in calls], ['xcrun','xcrun','xcrun','killall','xcrun','xcrun'])
        self.assertEqual(r['attempts'][0]['shutdown']['status'], 'TIMEOUT')
        self.assertEqual(r['attempts'][0]['status'], 'FAIL')
        self.assertEqual(r['attempts'][1]['status'], 'READY')

    def test_second_failure_is_terminal(self):
        r, calls, error = self.exercise([None, self.timeout(), self.timeout(), None, None, self.timeout()])
        self.assertIsInstance(error, subprocess.TimeoutExpired)
        self.assertEqual(len(r['attempts']), 2)
        self.assertTrue(all(a['status']=='FAIL' for a in r['attempts']))
        self.assertEqual(len(calls), 6)

    def test_non_ci_never_resets_service(self):
        r, calls, error = self.exercise([None, self.timeout(), self.timeout(), None, None], ci=False)
        self.assertIsNone(error)
        self.assertTrue(all(c.args[0][0]=='xcrun' for c in calls))
        self.assertEqual(len(r['attempts']), 2)

    def test_reset_timeout_fails_closed(self):
        r, calls, error = self.exercise([None, self.timeout(), self.timeout(), self.timeout()])
        self.assertIsInstance(error, subprocess.TimeoutExpired)
        self.assertEqual(len(calls), 4)
        self.assertEqual(r['attempts'][0]['status'], 'FAIL')

    def test_shutdown_nonzero_is_recorded(self):
        r, calls, error = self.exercise([subprocess.CalledProcessError(1,'boot'), subprocess.CompletedProcess('shutdown',1), None, None, None])
        self.assertIsNone(error)
        self.assertEqual(r['attempts'][0]['shutdown']['returncode'],1)

    def test_unexpected_shutdown_error_not_swallowed(self):
        r, calls, error = self.exercise([None, self.timeout(), OSError('missing executable')])
        self.assertIsInstance(error, OSError)
        self.assertEqual(len(calls), 3)
        self.assertEqual(r['attempts'][0]['status'], 'FAIL')

if __name__ == '__main__': unittest.main()
