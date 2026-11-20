import copy
import importlib.util
import json
import os
from pathlib import Path
from types import SimpleNamespace
import subprocess
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location(
    "friends_retry_optional", Path(__file__).with_name("friends-root-retry-probe.py")
)
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)

UDID = "10000000-2000-4000-8000-900000000000"
# Shape follows raw Xcode tests/summary metadata previously archived by the main
# simulator job. Failure details below are invented, not a real Friends result.
DEVICE = dict(architecture="x86_64", deviceId=UDID, modelName="iPhone 17 Pro Max",
              osVersion="26.1", platform="iOS Simulator")
CONFIG = dict(configurationId="1", configurationName="Test Scheme Action")


def result(failed=1):
    counts = dict(passedTests=0, failedTests=failed, skippedTests=0, expectedFailures=0)
    summary = dict(**counts, totalTestCount=failed, devicesAndConfigurations=[
        dict(**counts, device=copy.deepcopy(DEVICE), testPlanConfiguration=copy.deepcopy(CONFIG))
    ], testFailures=[dict(targetName="PUBOUITests", testIdentifierString=probe.IDENTIFIER,
                          failureText="opaque evidence should stay private")] if failed else [])
    case = dict(nodeType="Test Case", nodeIdentifier=probe.IDENTIFIER, result="Failed",
                children=[dict(nodeType="Failure Message", name="do not transmit")])
    suite = dict(nodeType="Test Suite", name=probe.SUITE, children=[case] if failed else [])
    bundle = dict(nodeType="UI test bundle", name="PUBOUITests", children=[suite])
    tree = dict(devices=[copy.deepcopy(DEVICE)], testPlanConfigurations=[copy.deepcopy(CONFIG)],
                testNodes=[dict(nodeType="Test Plan", name="PUBO", children=[bundle])])
    return summary, tree, suite, case


class FriendsFailureClassifierTests(unittest.TestCase):
    def classify(self, mutator=None, failed=1):
        summary, tree, suite, case = result(failed)
        if mutator:
            mutator(summary, tree, suite, case)
        return probe.failed_test_classification(summary, tree, "large", UDID)

    def test_only_affirmative_typed_shapes(self):
        self.assertEqual(self.classify(), "CASE_REPORTED_FAILED")
        self.assertEqual(self.classify(failed=0), "NO_CASE_RECORDED")
        self.assertEqual(self.classify(lambda s, t, u, c: t.update(testNodes=[]), failed=0),
                         "NO_CASE_RECORDED")
        self.assertEqual(self.classify(lambda s, t, u, c: t.update(testNodes=[])), "UNKNOWN")

    def test_wrong_simulator_configuration_or_suite(self):
        for change in [
            lambda s, t, u, c: s["devicesAndConfigurations"][0]["device"].update(deviceId="wrong"),
            lambda s, t, u, c: t["devices"][0].update(deviceId="wrong"),
            lambda s, t, u, c: t["devices"][0].update(modelName="iPhone 17"),
            lambda s, t, u, c: t["devices"][0].update(osVersion="26.0"),
            lambda s, t, u, c: t["devices"][0].update(architecture="arm64"),
            lambda s, t, u, c: t["testPlanConfigurations"][0].update(configurationId="2"),
            lambda s, t, u, c: u.update(name="FollowListParityUITests"),
            lambda s, t, u, c: t["testNodes"][0]["children"][0].update(name="AnotherBundle"),
            lambda s, t, u, c: s["testFailures"][0].update(targetName="AnotherBundle"),
        ]:
            with self.subTest(change=change):
                self.assertEqual(self.classify(change), "UNKNOWN")

    def test_unexpected_duplicated_missing_or_conflicting_cases(self):
        for change in [
            lambda s, t, u, c: u["children"].append(copy.deepcopy(c)),
            lambda s, t, u, c: u["children"].append(dict(c, nodeIdentifier="Other/testBad()")),
            lambda s, t, u, c: c.update(nodeIdentifier="Other/testBad()"),
            lambda s, t, u, c: c.update(result="Passed"),
            lambda s, t, u, c: c["children"].append(dict(c, nodeIdentifier="Other/testBad()")),
            lambda s, t, u, c: s["testFailures"][0].update(testIdentifierString="Other/testBad()"),
            lambda s, t, u, c: s.update(failedTests=True),
            lambda s, t, u, c: s.update(totalTestCount=2),
            lambda s, t, u, c: s["devicesAndConfigurations"][0].update(failedTests=0),
            lambda s, t, u, c: s.pop("testFailures"),
            lambda s, t, u, c: t.update(testNodes={"children": []}),
        ]:
            with self.subTest(change=change):
                self.assertEqual(self.classify(change), "UNKNOWN")
        self.assertEqual(self.classify(lambda s, t, u, c: u["children"].append(c), failed=0), "UNKNOWN")


class FriendsFailureReaderTests(unittest.TestCase):
    def read(self, contents, mode=None, size_limited=False):
        observed = []
        with tempfile.TemporaryDirectory() as tmp:
            private = Path(tmp)
            bundle = private / "friends.xcresult"
            if mode != "absent":
                bundle.mkdir()

            def run(command, *, stdout, stderr, timeout, check):
                observed.append(command[-3])
                self.assertEqual(command[:4], ["xcrun", "xcresulttool", "get", "test-results"])
                self.assertEqual(Path(stdout.name).parent, private)
                self.assertEqual(command[-2:], ["--path", str(bundle)])
                self.assertEqual(stderr, subprocess.DEVNULL)
                self.assertEqual(timeout, 8)
                self.assertFalse(check)
                if mode == "unreadable":
                    raise PermissionError("private")
                if mode == "timed_out":
                    raise subprocess.TimeoutExpired(command, timeout)
                stdout.write(contents[len(observed) - 1])
                return SimpleNamespace(returncode=17 if mode == "nonzero" else 0)

            with patch.object(probe.subprocess, "run", side_effect=run), patch.object(
                probe, "FAILURE_MAX_JSON", 2 if size_limited else 256 * 1024
            ):
                observed_result = probe.diagnose_exit_65(private, str(bundle), "large", UDID)
        return observed_result, observed

    def test_probes_only_two_private_bounded_metadata_files(self):
        s, t, _, _ = result()
        classification, calls = self.read([json.dumps(x).encode() for x in (s, t)])
        self.assertEqual((classification, calls), ("CASE_REPORTED_FAILED", ["summary", "tests"]))

    def test_absence_truncation_unreadability_malformed_and_oversize(self):
        for mode, payload, size_limited in [
            ("absent", b"{}", False),
            ("nonzero", b"{}", False),
            ("timed_out", b"{}", False),
            ("unreadable", b"{}", False),
            (None, b'{"truncated"', False),
            (None, b'{"x":1,"x":2}', False),
            (None, b'{"n":NaN}', False),
            (None, b'{"x": 1}', True),
        ]:
            with self.subTest(mode=mode, payload=payload):
                self.assertEqual(self.read([payload, payload], mode, size_limited)[0], "UNKNOWN")


class FriendsFailureRunBoundaryTests(unittest.TestCase):
    def run_failure(self, code):
        env = {
            "PUBO_SIM_SIZE": "large", "GITHUB_ACTIONS": "true",
            "GITHUB_REPOSITORY": "qianshou330-cyber/pubo-ios",
            "GITHUB_REF": "refs/heads/ui-four-tabs-148-20261112", "GITHUB_SHA": "a" * 40,
            "GITHUB_RUN_ID": "100", "GITHUB_RUN_ATTEMPT": "1",
        }
        commands = []

        def cmd(argv, *_args, **_kwargs):
            commands.append(argv)
            return code if argv[-1] == "test-without-building" else 0

        def check_output(argv, **_kwargs):
            if argv[0] == "xcodebuild":
                return probe.XCODE
            return env["GITHUB_SHA"] if argv[1] == "rev-parse" else probe.PINS[argv[-1]]

        with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, env), patch.multiple(
            probe, cmd=cmd, create_device=lambda *a: {"udid": UDID}, select_template=lambda *a: None,
            available_inventory=lambda: None, boot=lambda *a: None,
        ), patch.object(probe.platform, "machine", return_value="x86_64"), patch.object(
            probe.shutil, "which", return_value="/bin/xcodegen"
        ), patch.object(probe.subprocess, "check_output", side_effect=check_output), patch.object(
            probe, "diagnose_exit_65", return_value="CASE_REPORTED_FAILED"
        ) as diagnose:
            out = Path(tmp) / "published"
            self.assertEqual(probe.main(Path(tmp), out), 1)
            self.assertEqual(sorted(x.name for x in out.iterdir()), ["receipt.json"])
            receipt = json.loads((out / "receipt.json").read_text())
            self.assertEqual(receipt["status"], "NOT_PASSED")
            self.assertEqual(receipt["stage"], "XCTEST")
            self.assertEqual(receipt["testExitCode"], code)
            self.assertFalse(any("export" in argv for argv in commands))
            if code == 65:
                diagnose.assert_called_once()
                self.assertEqual(receipt["failureClassification"], "CASE_REPORTED_FAILED")
            else:
                diagnose.assert_not_called()
                self.assertNotIn("failureClassification", receipt)

    def test_exit_65_adds_enum_but_does_not_pass_or_export(self):
        self.run_failure(65)

    def test_other_nonzero_has_no_diagnostic_change(self):
        self.run_failure(17)


if __name__ == "__main__":
    unittest.main()
