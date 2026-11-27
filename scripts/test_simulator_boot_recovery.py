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


class PretestWarmupAndHandshakeClassifierTests(unittest.TestCase):
    def test_warmup_services_ready_on_first_probe(self):
        from simulator_boot import warmup_services
        with tempfile.TemporaryDirectory() as d:
            receipt = Path(d) / 'warmup.json'
            ok = subprocess.CompletedProcess(['xcrun'], 0, '', '')
            with patch('simulator_boot.subprocess.run', side_effect=[ok, ok]) as run:
                report = warmup_services('sim-udid', receipt, timeout=5)
            self.assertEqual(report['status'], 'READY')
            self.assertTrue(report['springBoardReady'])
            self.assertTrue(report['screenshotReady'])
            self.assertEqual(len(run.call_args_list), 2)
            self.assertEqual(json.loads(receipt.read_text())['status'], 'READY')

    def test_warmup_services_retries_then_ready(self):
        from simulator_boot import warmup_services
        fail = subprocess.CompletedProcess(['xcrun'], 1, '', 'not ready')
        ok = subprocess.CompletedProcess(['xcrun'], 0, '', '')
        with patch('simulator_boot.subprocess.run', side_effect=[fail, ok, ok]), patch('simulator_boot.time.sleep'):
            report = warmup_services('sim-udid', timeout=5)
        self.assertEqual(report['status'], 'READY')
        self.assertEqual(report['springBoardAttempts'], 2)
        self.assertEqual(report['screenshotAttempts'], 1)

    def test_zero_tests_ax_loaded_code18_matches(self):
        from simulator_boot import is_pretest_ax_handshake_failure
        zero = {'passedTests': 0, 'failedTests': 0, 'skippedTests': 0, 'expectedFailures': 0, 'totalTestCount': 0}
        matched, _ = is_pretest_ax_handshake_failure(
            zero, 'Testing failed: Error Domain=XCTDaemonErrorDomain Code=18 "Timed out waiting for AX loaded notification"'
        )
        self.assertTrue(matched)
        matched_no_summary, _ = is_pretest_ax_handshake_failure(
            None, 'XCTDaemonErrorDomain Code=18 during runner bootstrap'
        )
        self.assertTrue(matched_no_summary)
        summary_with_failure_text = dict(zero, testFailures=[{'message': 'Timed out waiting for AX loaded notification'}])
        self.assertTrue(is_pretest_ax_handshake_failure(summary_with_failure_text, '')[0])

    def test_any_executed_test_or_real_failure_never_matches(self):
        from simulator_boot import is_pretest_ax_handshake_failure
        code18 = 'Error Domain=XCTDaemonErrorDomain Code=18 "Timed out waiting for AX loaded notification"'
        base = {'passedTests': 0, 'failedTests': 0, 'skippedTests': 0, 'expectedFailures': 0, 'totalTestCount': 0}
        for key in ('passedTests', 'failedTests', 'skippedTests', 'expectedFailures', 'totalTestCount'):
            for bad_val in (1, True):
                with self.subTest(key=key, bad_val=bad_val):
                    self.assertFalse(is_pretest_ax_handshake_failure(dict(base, **{key: bad_val}), code18)[0])
        device_ran = dict(base, devicesAndConfigurations=[{'passedTests': 1, 'failedTests': 0}])
        self.assertFalse(is_pretest_ax_handshake_failure(device_ran, code18)[0])
        self.assertFalse(is_pretest_ax_handshake_failure(base, 'XCTAssertTrue failed')[0])
        self.assertFalse(is_pretest_ax_handshake_failure(base, 'Timed out while evaluating UI query')[0])

    def test_resolve_xctestrun_fail_closed(self):
        from simulator_boot import resolve_xctestrun
        self.assertIsNone(resolve_xctestrun(''))
        with tempfile.TemporaryDirectory() as d:
            valid = Path(d) / 'PUBO_iphonesimulator26.0-arm64.xctestrun'
            valid.write_text('<?xml version="1.0"?>')
            self.assertEqual(resolve_xctestrun(str(valid)), str(valid))
            link = Path(d) / 'link.xctestrun'
            link.symlink_to(valid)
            with self.assertRaises(ValueError):
                resolve_xctestrun(str(link))
            wrong = Path(d) / 'not-run.txt'
            wrong.write_text('x')
            with self.assertRaises(ValueError):
                resolve_xctestrun(str(wrong))


if __name__ == '__main__': unittest.main()
