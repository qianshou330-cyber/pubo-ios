"""Optional, one exact synthetic Friends test on one task-owned C85 simulator."""
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import re
import shutil
import signal
import struct
import subprocess
import sys
import time

from four_tabs_gate import complete
from iphone_qa_matrix import MATRIX, RUNTIME, available_inventory, create_device, select_template, summary_matches_device
from simulator_boot import boot
from verify_navigation_shards import png, read_json

SUITE = "FriendsRootRetryUITests"
METHOD = "testOlderFailureRetriesAtExistingCursor"
IDENTIFIER = f"{SUITE}/{METHOD}()"
LABEL = "friends-root-retry-existing-cursor"
XCODE = "Xcode 26.0.1\nBuild version 17A400"
BASE = "581f88f99fb24c2049c0db8cea57ff730bd71f84"
PINS = {
    "App/Features/FriendsView.swift": "fd85bde1c62442233c3694070403163dfb9f9d99",
    "App/Infrastructure/FixtureTransport.swift": "41d439920341f1c1f71a1f226b8e7ec76c81f006",
    "App/Infrastructure/AppSession.swift": "5386324a0b3dec05526dd584e3185f94cd07971f",
    "UITests/FollowListParityUITests.swift": "5448cbaef8240456ceea54e33685729ab9924b6a",
    "project.yml": "a8380cf91b2570ddbdfc71be2c59f8192ef44244",
    "scripts/brand-assets.swift": "d269df2ff106d3de4bc12960fd84d474cd11e0c1",
    "scripts/four_tabs_gate.py": "fe25228acfb856c4f6358be0000d3e8999d19b40",
    "scripts/verify_navigation_shards.py": "d58babc0b16cca54ee7dec68054da37d1911b817",
    "scripts/iphone_qa_matrix.py": "88542174097d774ec808e915c4ad20fdd5587e76",
    "scripts/iphone-qa-matrix.json": "d1850ade1d1b2291658f5e2332fb718282f42610",
    "scripts/simulator_boot.py": "b944ca9087861e7b8fc0431c50bbc92d788743f2",
    ".github/workflows/four-tabs.yml": "828109a7cf95d4e3c9222045edeeebc47d661051",
}


def require(value):
    if not value:
        raise ValueError("Optional evidence contract not met")


def one_method(tree):
    got = []

    def walk(nodes, suite=None, bundle=None):
        require(isinstance(nodes, list))
        for node in nodes:
            require(isinstance(node, dict))
            kind = node.get("nodeType")
            identity = node.get("name") or node.get("nodeIdentifier")
            n_suite = identity if kind == "Test Suite" else suite
            n_bundle = identity if kind == "Test Bundle" else bundle
            kids = node.get("children", [])
            if kind == "Test Case":
                require(node.get("nodeIdentifier") == IDENTIFIER and node.get("result") == "Passed"
                        and (suite is None or suite == SUITE) and (bundle is None or bundle == "PUBOUITests")
                        and kids == [])
                got.append(IDENTIFIER)
            walk(kids, n_suite, n_bundle)

    walk(tree["testNodes"])
    require(got == [IDENTIFIER])


def verified_picture(export, size, udid, start, end):
    manifest = read_json(export / "manifest.json")
    require(isinstance(manifest, list) and len(manifest) == 1 and manifest[0]["testIdentifier"] == IDENTIFIER)
    attachments = manifest[0]["attachments"]
    require(isinstance(attachments, list))
    matches = [a for a in attachments if re.fullmatch(LABEL + r"_[0-9]+_[0-9A-Fa-f-]{36}\.png",
                                                        a.get("suggestedHumanReadableName", ""))]
    require(len(matches) == 1)
    a = matches[0]
    filename, timestamp = a["exportedFileName"], a["timestamp"]
    require(re.fullmatch(r"[0-9A-Fa-f-]{36}\.png", filename) and a["deviceId"] == udid
            and a["isAssociatedWithFailure"] is False and type(timestamp) in (int, float)
            and math.isfinite(timestamp) and start <= timestamp <= end)
    file = export / filename
    require(file.is_file() and not file.is_symlink() and 0 < file.stat().st_size <= 16 * 1024 * 1024)
    digest = png(file)  # Unmodified C85 strict PNG validator.
    with file.open("rb") as data:
        width, height = struct.unpack(">II", data.read(24)[16:24])
    profile = MATRIX[size]
    require((width, height) == (3 * profile["width"], 3 * profile["height"]))
    return file, {"sha256": digest, "width": width, "height": height, "timestamp": timestamp}


def cmd(args, log, timeout, stdout=None):
    with log.open("ab") as err, (stdout or log).open("ab") as out:
        process = subprocess.Popen(args, stdout=out, stderr=err, start_new_session=True)
        try:
            return process.wait(timeout)
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(15)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait(10)


# Only a fixed enum may leave runner-private storage on an exit-65 failure.
# The Xcode result does not identify the root cause or prove that startup failed.
FAILURE_UNKNOWN = "UNKNOWN"
FAILURE_MAX_JSON = 256 * 1024
FAILURE_READ_TIMEOUT = 8


def failed_test_classification(summary, tree, size, udid):
    try:
        expected_device = {
            "architecture": "x86_64", "deviceId": udid, "modelName": MATRIX[size]["model"],
            "osVersion": MATRIX["osVersion"], "platform": "iOS Simulator",
        }

        def is_device(device):
            return all(device.get(key) == value for key, value in expected_device.items())

        configs = summary["devicesAndConfigurations"]
        devices, tree_configs = tree["devices"], tree["testPlanConfigurations"]
        require(all(isinstance(items, list) and len(items) == 1
                    for items in (configs, devices, tree_configs)))
        run = configs[0]
        require(is_device(run["device"]) and is_device(devices[0]))
        config = run["testPlanConfiguration"]
        require(isinstance(config, dict) and isinstance(tree_configs[0], dict)
                and isinstance(config.get("configurationId"), str) and config["configurationId"]
                and config == tree_configs[0])

        failed = summary["failedTests"]
        require(type(failed) is int and failed in (0, 1))
        counts = {"passedTests": 0, "failedTests": failed, "skippedTests": 0, "expectedFailures": 0}
        require(all(type(item.get(key)) is int and item[key] == value
                    for item in (summary, run) for key, value in counts.items()))
        require(type(summary.get("totalTestCount")) is int and summary["totalTestCount"] == failed)
        failures = summary["testFailures"]
        require(isinstance(failures, list) and len(failures) == failed)
        require(all(row.get("targetName") == "PUBOUITests"
                    and row.get("testIdentifierString") == IDENTIFIER for row in failures))

        nodes = tree["testNodes"]
        for kinds, name in ((("Test Plan",), "PUBO"), (("UI test bundle", "Test Bundle"), "PUBOUITests"),
                            (("Test Suite",), SUITE)):
            if not failed and nodes == []:
                return "NO_CASE_RECORDED"
            require(isinstance(nodes, list) and len(nodes) == 1)
            parent = nodes[0]
            require(parent.get("nodeType") in kinds and parent.get("name") == name)
            nodes = parent.get("children", [])
        if not failed and nodes == []:
            return "NO_CASE_RECORDED"
        require(failed == 1 and isinstance(nodes, list) and len(nodes) == 1)
        case = nodes[0]
        require(case.get("nodeType") == "Test Case" and case.get("nodeIdentifier") == IDENTIFIER
                and case.get("result") == "Failed")
        children = case.get("children", [])
        require(isinstance(children, list) and all(child.get("nodeType") == "Failure Message"
                                                   and child.get("children", []) == [] for child in children))
        return "CASE_REPORTED_FAILED"
    except (AttributeError, KeyError, TypeError, ValueError):
        return FAILURE_UNKNOWN


def diagnose_exit_65(private, bundle, size, udid):
    try:
        result = Path(bundle)
        if not result.is_dir() or result.is_symlink():
            return FAILURE_UNKNOWN
        data = []
        for kind in ("summary", "tests"):
            path = private / f"exit65-{kind}.json"
            with path.open("xb") as output:
                probe = subprocess.run(
                    ["xcrun", "xcresulttool", "get", "test-results", kind, "--path", bundle],
                    stdout=output, stderr=subprocess.DEVNULL, timeout=FAILURE_READ_TIMEOUT, check=False,
                )
            require(probe.returncode == 0 and 0 < path.stat().st_size <= FAILURE_MAX_JSON)
            data.append(read_json(path))
        return failed_test_classification(*data, size, udid)
    except (OSError, ValueError, RecursionError, subprocess.SubprocessError):
        return FAILURE_UNKNOWN


def main(private, out):
    size = os.environ.get("PUBO_SIM_SIZE")
    out.mkdir(parents=True, exist_ok=False)
    receipt = {"schema": 1, "scope": "OPTIONAL_SYNTHETIC_FRIENDS_CURSOR_ONLY", "status": "UNAVAILABLE",
               "base": BASE, "size": size, "method": IDENTIFIER, "stage": "IDENTITY"}
    udid = None
    try:
        require(size in ("small", "large") and platform.machine() == "x86_64")
        require(os.environ.get("GITHUB_ACTIONS") == "true"
                and os.environ.get("GITHUB_REPOSITORY") == "qianshou330-cyber/pubo-ios"
                and os.environ.get("GITHUB_REF") == "refs/heads/ui-four-tabs-148-20261112")
        head = os.environ["GITHUB_SHA"]
        run_id, attempt = os.environ["GITHUB_RUN_ID"], os.environ["GITHUB_RUN_ATTEMPT"]
        require(re.fullmatch(r"[0-9a-f]{40}", head)
                and all(re.fullmatch(r"[1-9][0-9]*", n) for n in (run_id, attempt)))
        require(subprocess.check_output(["git", "rev-parse", "HEAD"], text=True, timeout=15).strip() == head)
        receipt.update(commit=head, runId=run_id, runAttempt=attempt, model=MATRIX[size]["model"],
                       runtime=RUNTIME, xcode=XCODE)
        for path, expected in PINS.items():
            require(subprocess.check_output(["git", "hash-object", path], text=True, timeout=15).strip() == expected)
        require(subprocess.check_output(["xcodebuild", "-version"], text=True, timeout=30).strip() == XCODE)

        log = private / "private-execution.log"
        receipt["stage"] = "BUILD"
        if shutil.which("xcodegen") is None:
            require(cmd(["brew", "install", "xcodegen"], log, 600) == 0)
        require(cmd(["swift", "scripts/brand-assets.swift"], log, 180) == 0)
        require(cmd(["xcodegen", "generate"], log, 180) == 0)
        derived = str(private / "debug")
        xcode = ["xcodebuild", "-project", "PUBO.xcodeproj", "-scheme", "PUBO", "-configuration", "Debug"]
        require(cmd(xcode + ["-sdk", "iphonesimulator", "-destination", "generic/platform=iOS Simulator",
                             "-derivedDataPath", derived, "CODE_SIGNING_ALLOWED=NO", "ARCHS=x86_64",
                             "ONLY_ACTIVE_ARCH=YES", "build-for-testing"], log, 1200) == 0)
        receipt["stage"] = "BOOT"
        device = create_device(size, select_template(available_inventory(), size), "PUBO friends root retry " + size)
        udid = device["udid"]
        receipt["deviceId"] = udid
        boot(udid, private / "boot.json")
        receipt["stage"] = "XCTEST"
        bundle = str(private / "friends.xcresult")
        start = time.time()
        rc = cmd(xcode + ["-destination", "platform=iOS Simulator,id=" + udid, "-destination-timeout", "90",
                          "-derivedDataPath", derived, "-resultBundlePath", bundle, "-parallel-testing-enabled", "NO",
                          f"-only-testing:PUBOUITests/{SUITE}/{METHOD}", "CODE_SIGNING_ALLOWED=NO",
                          "test-without-building"], log, 900)
        end = time.time()
        receipt["testExitCode"] = rc
        receipt["status"] = "NOT_PASSED"
        if rc == 65:
            receipt["failureClassification"] = diagnose_exit_65(private, bundle, size, udid)
        require(rc == 0)
        receipt["stage"] = "EVIDENCE"
        receipt["status"] = "UNAVAILABLE"
        for kind in ("summary", "tests"):
            require(cmd(["xcrun", "xcresulttool", "get", "test-results", kind, "--path", bundle],
                        log, 90, private / (kind + ".json")) == 0)
        summary = read_json(private / "summary.json")
        require(complete(summary, 1) and summary_matches_device(summary, size, udid, 1))
        one_method(read_json(private / "tests.json"))
        export = private / "attachment"
        require(cmd(["xcrun", "xcresulttool", "export", "attachments", "--path", bundle,
                     "--output-path", str(export)], log, 90) == 0)
        file, proof = verified_picture(export, size, udid, start, end)
        published = out / (LABEL + ".png")
        shutil.copyfile(file, published)
        require(hashlib.sha256(published.read_bytes()).hexdigest() == proof["sha256"])
        receipt.update(status="PASS_SCOPE_ONLY", stage="COMPLETE", screenshot=proof)
    except (OSError, RuntimeError, ValueError, KeyError, TypeError, AttributeError, subprocess.SubprocessError):
        # Do not print exception text (can include arbitrary host paths or raw output).
        (out / (LABEL + ".png")).unlink(missing_ok=True)
    finally:
        if udid:
            for action in ("shutdown", "delete"):
                try:
                    cmd(["xcrun", "simctl", action, udid], private / "private-execution.log", 60)
                except (OSError, subprocess.SubprocessError):
                    pass
        (out / "receipt.json").write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print("Friends synthetic retry:", receipt["status"], receipt["stage"], flush=True)
    return 0 if receipt["status"] == "PASS_SCOPE_ONLY" else 1


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("Need private scratch dir and fresh evidence dir")
    raise SystemExit(main(Path(sys.argv[1]), Path(sys.argv[2])))
