"""C99 reconstructed Debug Simulator evidence only. No live transport or packaging."""
import binascii
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import platform
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib

BASE = "7abc4b1c1c9e2395350a9b15992e987243ceb303"
REPO = "qianshou330-cyber/pubo-ios"
REF = "refs/heads/diag-c99-native-focus"
NEW = {".github/workflows/c99-native-focus.yml", "diagnostics/c99/focus.py"}
STOCK = ".github/workflows/four-tabs.yml"
PIN = {
    STOCK: "33762b7334f954b77c9ddedd65b4e7ff0d548447",
    "scripts/iphone_qa_matrix.py": "88542174097d774ec808e915c4ad20fdd5587e76",
    "scripts/iphone-qa-matrix.json": "d1850ade1d1b2291658f5e2332fb718282f42610",
}
CHANGED = {
    "App/Features/ProfileView.swift": "84841e78347bb4f27c9d5b687dcda212ce1cee69",
    "App/Features/TimelineView.swift": "203f03c4d2c5c8fc81f3664da0dc5ff2c392b767",
    "App/Infrastructure/C99WorldRetryProbe.swift": "d506d7b371ef155f60b448ae9adadc0c160bb759",
    "App/Infrastructure/FixtureTransport.swift": "9e8988d7c432b35e51f6a1fb6574f151deeb70ce",
    "UITests/C99FriendsChildHandlesUITests.swift": "11dca45c0a1dc0ecb985f2c8168d145b21622893",
    "UITests/C99WorldRetryUITests.swift": "d384ed7bb10485d9762bf3ac8efc766f726c8f1f",
    "scripts/test_visibility_capture_integration.py": "f0e6d7cecf4dbed8b9d6ca1eba52cd9972ffb910",
    "scripts/timeline-capture-bench/run.py": "52944a6338d1e0473e06d5fe7247d7eeaa191c5d",
}
WORLD = "C99WorldRetryUITests/testRecommendedRealRetryKeepsSameFeedDuringHeldRead()"
FOLLOWING = "C99FriendsChildHandlesUITests/testFollowingFromFriends()"
FOLLOWERS = "C99FriendsChildHandlesUITests/testFollowersFromFriends()"
EXPECTED = {
    "world": {WORLD: ("c99-world-initial-503", "c99-world-retry-pending", "c99-world-retry-restored")},
    "friends": {FOLLOWING: ("C99-Friends-following",), FOLLOWERS: ("C99-Friends-followers",)},
}
UUID = r"[A-Fa-f0-9]{8}(?:-[A-Fa-f0-9]{4}){3}-[A-Fa-f0-9]{12}"
URL = "test://com.apple.xcode/PUBO/PUBOUITests/"
DIMS = {"small": (1206, 2622), "large": (1320, 2868)}
MODEL = {"small": "iPhone 17", "large": "iPhone 17 Pro Max"}
CONFIG = "Test Scheme Action"
RUNTIME = "com.apple.CoreSimulator.SimRuntime.iOS-26-1"


class Reject(ValueError):
    """Only program-authored enum literals may reach the public state."""


def need(ok, category):
    if not ok:
        raise Reject(category)


def command(argv, timeout=60, capture=False, check=True):
    return subprocess.run(argv, check=check, stdin=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                          stdout=subprocess.PIPE if capture else subprocess.DEVNULL, timeout=timeout)


def textout(*argv):
    return command(argv, capture=True).stdout.decode("utf-8").strip()


def preflight(head):
    need(textout("git", "rev-parse", "HEAD") == head and
         textout("git", "log", "-1", "--format=%P") == BASE and
         textout("git", "rev-parse", "HEAD^1^{tree}") == "c8521dbc2309cc74c2024157856c63488f98be77",
         "SOURCE_REJECTED")
    # Compare tracked files, modes, changed names, and actual object identities before generating the project.
    need(not textout("git", "status", "--porcelain=v1", "--untracked-files=all"), "SOURCE_REJECTED")
    changed = set(textout("git", "diff", "--no-renames", "--name-only", BASE, head).splitlines())
    need(changed == NEW | set(CHANGED), "SOURCE_REJECTED")
    for p in NEW | set(CHANGED) | set(PIN):
        entry = textout("git", "ls-tree", head, "--", p).split()
        need(len(entry) == 4 and entry[:2] == ["100644", "blob"] and
             entry[2] == (CHANGED | PIN).get(p, entry[2]) and entry[3] == p, "SOURCE_REJECTED")
    need(platform.machine() == "x86_64" and platform.system() == "Darwin" and
         textout("xcodebuild", "-version") == "Xcode 26.0.1\nBuild version 17A400", "HOST_REJECTED")


def unique(pairs):
    result = dict(pairs)
    need(len(result) == len(pairs), "AMBIGUOUS_JSON")
    return result


def parse(data):
    need(len(data) <= 2_000_000, "UNSUPPORTED_SCHEMA")
    return json.loads(data, object_pairs_hook=unique, parse_constant=lambda _: need(False, "UNSUPPORTED_SCHEMA"))


def native_summary(summary, size, device, count):
    need(set(summary) == {"devicesAndConfigurations", "environmentDescription", "expectedFailures", "failedTests",
                          "finishTime", "passedTests", "result", "skippedTests", "startTime", "statistics",
                          "testFailures", "title", "topInsights", "totalTestCount"}, "SUMMARY_REJECTED")
    need(all(type(summary[k]) in (int, float) and math.isfinite(summary[k]) for k in ("startTime", "finishTime"))
         and summary["startTime"] < summary["finishTime"], "SUMMARY_REJECTED")
    configs = summary["devicesAndConfigurations"]
    need(type(configs) is list and len(configs) == 1, "SUMMARY_REJECTED")
    row = configs[0]
    need(set(row) == {"device", "expectedFailures", "failedTests", "passedTests", "skippedTests",
                      "testPlanConfiguration"}, "SUMMARY_REJECTED")
    want = {"deviceId": device["udid"], "deviceName": device["name"], "modelName": MODEL[size],
            "osVersion": "26.1", "platform": "iOS Simulator", "architecture": "x86_64"}
    need(all(row["device"].get(k) == v for k, v in want.items()) and
         row["testPlanConfiguration"]["configurationName"] == CONFIG, "DEVICE_REJECTED")
    need(type(summary.get("totalTestCount")) is int and summary["totalTestCount"] == count,
         "SUMMARY_REJECTED")
    keys = ("passedTests", "failedTests", "skippedTests", "expectedFailures")
    counts = {k: row.get(k) for k in keys}
    need(all(type(v) is int and v >= 0 and type(summary.get(k)) is int and summary[k] == v
             for k, v in counts.items()) and sum(counts.values()) == count, "SUMMARY_REJECTED")
    need(summary["result"] in ("Passed", "Failed"), "SUMMARY_REJECTED")
    return counts


def case_tree(tree, expected):
    # Exactly one plan, one UI test bundle, one route suite, and one instance of every chosen case.
    # Children cannot be hidden beneath unrecognized wrappers. Runtime warning text stays local.
    klass = next(iter(expected)).split("/")[0]
    need(set(tree) == {"testNodes", "devices", "testPlanConfigurations"}, "TREE_REJECTED")
    def only(nodes, kind, name, url=None):
        fields = {"nodeType", "name", "result", "children"} | ({"nodeIdentifierURL"} if url else set())
        need(type(nodes) is list and len(nodes) == 1 and set(nodes[0]) == fields and
             nodes[0]["nodeType"] == kind and nodes[0]["name"] == name and
             nodes[0]["result"] in ("Passed", "Failed") and
             (url is None or nodes[0]["nodeIdentifierURL"] == url), "TREE_REJECTED")
        return nodes[0]["children"]
    nodes = only(tree["testNodes"], "Test Plan", "PUBO")
    nodes = only(nodes, "UI test bundle", "PUBOUITests", URL.rstrip("/"))
    nodes = only(nodes, "Test Suite", klass, URL + klass)
    need(type(nodes) is list and len(nodes) == len(expected), "TREE_REJECTED")
    seen = {}
    for node in nodes:
        allowed = {"duration", "durationInSeconds", "name", "nodeIdentifier", "nodeIdentifierURL", "nodeType", "result"}
        need(set(node) in (allowed, allowed | {"children"}), "TREE_REJECTED")
        ident = node["nodeIdentifier"]
        need(node["nodeType"] == "Test Case" and ident in expected and ident not in seen and
             node["name"] == ident.split("/")[1] and node["nodeIdentifierURL"] == URL + ident[:-2],
             "TREE_REJECTED")
        result = node["result"]
        need(result in ("Passed", "Failed", "Skipped", "Expected Failure"), "TREE_REJECTED")
        children = node.get("children", [])
        need(type(children) is list and len(children) <= 32, "TREE_REJECTED")
        warnings = 0
        for child in children:
            kind = child["nodeType"]
            need(set(child) == {"nodeType", "name"} and type(child["name"]) is str, "TREE_REJECTED")
            if kind == "Runtime Warning":
                warnings += 1
            else:
                need(kind == "Failure Message" and result == "Failed", "TREE_REJECTED")
        seen[ident] = {"result": result, "runtimeWarningCount": warnings}
    need(set(seen) == set(expected), "TREE_REJECTED")
    return seen


def case_state(summary, tree, size, device, expected):
    counts = native_summary(summary, size, device, len(expected))
    row = summary["devicesAndConfigurations"][0]
    need(tree["devices"] == [row["device"]] and
         set(row["device"]) == {"architecture", "deviceId", "deviceName", "modelName", "osBuildNumber", "osVersion", "platform"} and
         tree["testPlanConfigurations"] == [row["testPlanConfiguration"]] ==
         [{"configurationId": "1", "configurationName": CONFIG}], "DEVICE_REJECTED")
    cases = case_tree(tree, expected)
    for result, key in (("Passed", "passedTests"), ("Failed", "failedTests"),
                        ("Skipped", "skippedTests"), ("Expected Failure", "expectedFailures")):
        need(sum(case["result"] == result for case in cases.values()) == counts[key], "SUMMARY_REJECTED")
    if counts["passedTests"] == len(expected):
        node = tree["testNodes"][0]
        for _ in range(3):
            need(node["result"] == "Passed", "TREE_REJECTED")
            node = node["children"][0]
        need(summary["result"] == "Passed" and summary["testFailures"] == [], "SUMMARY_REJECTED")
    return cases


def png_check(data, size):
    # Accept only original RGB/A 8-bit, noninterlaced XCTest screenshots at the device resolution.
    # Permit known static Screenshot metadata, not arbitrary text, EXIF/GPS, profiles or trailers.
    w, h = DIMS[size]
    need(data[:8] == b"\x89PNG\r\n\x1a\n", "PNG_REJECTED")
    pos, kinds, parts = 8, [], []
    exif = (bytes.fromhex("4d4d002a000000080003010e00020000000b0000003201120003000000010001000087690004000000010000003e0000000053637265656e73686f7400000003928600070000001200000068a002000400000001")
            + struct.pack(">I", w) + bytes.fromhex("a003000400000001") + struct.pack(">I", h)
            + bytes.fromhex("00000000415343494900000053637265656e73686f74"))
    channels = None
    while pos < len(data):
        need(pos + 12 <= len(data), "PNG_REJECTED")
        n, kind = struct.unpack_from(">I4s", data, pos)
        need(pos + 12 + n <= len(data) and len(kinds) < 8192, "PNG_REJECTED")
        body = data[pos+8:pos+8+n]
        need(binascii.crc32(kind + body) == struct.unpack_from(">I", data, pos+8+n)[0], "PNG_REJECTED")
        pos += n + 12
        if not kinds:
            need(kind == b"IHDR" and len(body) == 13 and body[:8] == struct.pack(">II", w, h)
                 and body[8:] in (b"\x08\x02\x00\x00\x00", b"\x08\x06\x00\x00\x00"), "PNG_REJECTED")
            channels = {2: 3, 6: 4}[body[9]]
        elif kind == b"IDAT":
            need(b"IDAT" not in kinds or kinds[-1] == b"IDAT", "PNG_REJECTED")
            parts.append(body)
        elif kind == b"IEND":
            need(n == 0 and parts and pos == len(data), "PNG_REJECTED")
        else:
            need(kind not in kinds and not parts and (
                (kind == b"sRGB" and body == b"\x00") or (kind == b"eXIf" and body == exif) or
                (kind == b"iTXt" and hashlib.sha256(body).hexdigest() ==
                 "861617ee5fefbed9354987559086a994ffc207a0c9999d379568b0759fd79574")), "PNG_REJECTED")
        kinds.append(kind)
    need(kinds and kinds[-1] == b"IEND", "PNG_REJECTED")
    stride = w * channels + 1
    decoder = zlib.decompressobj()
    pixels = decoder.decompress(b"".join(parts), stride*h + 1)
    need(len(pixels) == stride*h and decoder.eof and not decoder.unused_data and not decoder.unconsumed_tail
         and all(f <= 4 for f in pixels[::stride]), "PNG_REJECTED")


def original_bytes(manifest, directory, expected, size, device, summary):
    need(type(manifest) is list and len(manifest) == len(expected) and not directory.is_symlink(),
         "ATTACHMENT_REJECTED")
    files, owners, found, stamps = set(), set(), {}, {}
    for row in manifest:
        need(set(row) == {"testIdentifier", "testIdentifierURL", "attachments"}, "ATTACHMENT_REJECTED")
        owner = row["testIdentifier"]
        need(owner in expected and owner not in owners and row["testIdentifierURL"] == URL + owner[:-2],
             "ATTACHMENT_REJECTED")
        owners.add(owner)
        items = row["attachments"]
        need(type(items) is list and len(items) == len(expected[owner]), "ATTACHMENT_REJECTED")
        for a in items:
            need(set(a) == {"configurationName", "deviceId", "deviceName", "exportedFileName",
                            "isAssociatedWithFailure", "suggestedHumanReadableName", "timestamp"}
                 and a["configurationName"] == CONFIG and a["deviceId"] == device["udid"]
                 and a["deviceName"] == device["name"] and a["isAssociatedWithFailure"] is False
                 and type(a["timestamp"]) in (int, float)
                 and summary["startTime"] <= a["timestamp"] <= summary["finishTime"],
                 "ATTACHMENT_REJECTED")
            suggested = a["suggestedHumanReadableName"]
            matches = [slot for slot in expected[owner] if re.fullmatch(
                re.escape(slot) + ("(?:\\.png)?" if owner in (FOLLOWERS, FOLLOWING) else "") +
                r"_0_" + UUID + r"\.png", suggested)]
            need(len(matches) == 1 and matches[0] not in found, "ATTACHMENT_REJECTED")
            filename = a["exportedFileName"]
            need(re.fullmatch(UUID + r"\.png", filename) and filename not in files, "ATTACHMENT_REJECTED")
            files.add(filename)
            p = directory / filename
            need(not p.is_symlink() and p.is_file() and 33 < p.stat().st_size <= 24_000_000, "PNG_REJECTED")
            data = p.read_bytes()
            png_check(data, size)
            found[matches[0]] = data
            stamps[matches[0]] = a["timestamp"]
    need(owners == set(expected) and set(found) == {s for slots in expected.values() for s in slots}
         and len({hashlib.sha256(v).digest() for v in found.values()}) == len(found), "ATTACHMENT_REJECTED")
    if WORLD in expected:
        order = [stamps[label] for label in expected[WORLD]]
        need(order[0] < order[1] < order[2], "ATTACHMENT_REJECTED")
    return found


def qa_helper():
    spec = importlib.util.spec_from_file_location("pubo_c98_qa", "scripts/iphone_qa_matrix.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def native(private, state, size, area):
    expected = EXPECTED[area]
    state["status"] = "SETUP_UNAVAILABLE"
    preflight(state["commit"])
    qa = qa_helper()
    need(qa.RUNTIME == RUNTIME and qa.MATRIX[size]["model"] == MODEL[size]
         and tuple(3*qa.MATRIX[size][k] for k in ("width", "height")) == DIMS[size], "DEVICE_REJECTED")
    template = qa.select_template(qa.available_inventory(), size)
    if not shutil.which("xcodegen"):
        command(["brew", "install", "xcodegen"], 600)
    command(["swift", "scripts/brand-assets.swift"], 120)
    command(["xcodegen", "generate"], 120)
    name = "C99 " + MODEL[size]
    device = qa.create_device(size, template, name)
    identifier = device["udid"]
    try:
        command(["xcrun", "simctl", "boot", identifier], 90)
        command(["xcrun", "simctl", "bootstatus", identifier, "-b"], 240)
        result = private / "focused.xcresult"
        state["status"] = "NATIVE_UNAVAILABLE"
        args = ["xcodebuild", "-project", "PUBO.xcodeproj", "-scheme", "PUBO", "-configuration", "Debug",
                "-sdk", "iphonesimulator", "-destination", "platform=iOS Simulator,id="+identifier,
                "-derivedDataPath", str(private/"dd"), "-resultBundlePath", str(result),
                "-parallel-testing-enabled", "NO", "-test-iterations", "1"]
        args += ["-only-testing:PUBOUITests/"+method[:-2] for method in expected]
        args += ["CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO", "ARCHS=x86_64",
                 "ONLY_ACTIVE_ARCH=YES", "test"]
        rc = command(args, 2100, check=False).returncode
        state["nativeExitZero"] = rc == 0
        state["status"] = "RESULT_UNAVAILABLE"
        def result_json(kind):
            return parse(command(["xcrun", "xcresulttool", "get", "test-results", kind,
                                  "--path", str(result)], 90, capture=True).stdout)
        summary = result_json("summary")
        state["cases"] = case_state(summary, result_json("tests"), size, device, expected)
        need(rc == 0, "NATIVE_NONZERO")
        need(all(c["result"] == "Passed" and c["runtimeWarningCount"] == 0 for c in state["cases"].values()),
             "CASE_GATE_REJECTED")
        state["status"] = "ATTACHMENTS_UNAVAILABLE"
        attachment_dir = private/"exports"
        attachment_dir.mkdir(mode=0o700)
        command(["xcrun", "xcresulttool", "export", "attachments", "--path", str(result),
                 "--output-path", str(attachment_dir)], 120)
        manifest = attachment_dir/"manifest.json"
        need(not attachment_dir.is_symlink() and manifest.is_file() and not manifest.is_symlink()
             and manifest.stat().st_size <= 2_000_000, "ATTACHMENT_REJECTED")
        return original_bytes(parse(manifest.read_bytes()), attachment_dir, expected, size, device, summary)
    finally:
        # Fresh device UUID validated by the pinned constructor; the hosted VM is also ephemeral.
        for verb in ("shutdown", "delete"):
            try:
                command(["xcrun", "simctl", verb, identifier], 30, check=False)
            except (OSError, subprocess.TimeoutExpired):
                pass


def run(args, env, runner=native):
    size, area = args
    head, run_id, attempt = env["GITHUB_SHA"], env["GITHUB_RUN_ID"], env["GITHUB_RUN_ATTEMPT"]
    need(size in DIMS and area in EXPECTED and env.get("GITHUB_REPOSITORY") == REPO
         and env.get("GITHUB_REF") == REF and env.get("GITHUB_EVENT_NAME") == "push"
         and re.fullmatch("[0-9a-f]{40}", head) and re.fullmatch("[1-9][0-9]{0,19}", run_id)
         and re.fullmatch("[1-9][0-9]{0,5}", attempt), "CONTEXT_REJECTED")
    base = Path(env["RUNNER_TEMP"])
    destination = base/"c99-publish"
    need(not os.path.lexists(destination), "DESTINATION_EXISTS")
    state = dict(schema=1, commit=head, run=run_id, attempt=attempt, area=area,
                 model=MODEL[size], os="26.1", xcodePin="26.0.1/17A400", cases={},
                 status="UNAVAILABLE", nativeExitZero=None, captures={})
    with tempfile.TemporaryDirectory(dir=base) as tmp:
        private = Path(tmp)
        stage = private/"safe"
        stage.mkdir(mode=0o700)
        try:
            captures = runner(private, state, size, area)
        except Reject as err:
            state["status"] = err.args[0]  # callers pass only fixed enum constants
            captures = {}
        except (OSError, ValueError, TypeError, KeyError, IndexError, AttributeError, RecursionError,
                struct.error, zlib.error, subprocess.SubprocessError):
            captures = {}  # retain fixed phase, never emit arbitrary error/AX/attachment text
        if captures:
            for label, data in captures.items():
                (stage/("original-"+label+".png")).write_bytes(data)
                state["captures"][label] = {"sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)}
            state["status"] = "VERIFIED_SYNTHETIC_ROW"
        (stage/"state.json").write_text(json.dumps(state, sort_keys=True, indent=2)+"\n", encoding="ascii")
        stage.rename(destination)
        with open(env["GITHUB_OUTPUT"], "a", encoding="ascii") as f:
            f.write("ready=true\n")
    return 0 if state["status"] == "VERIFIED_SYNTHETIC_ROW" else 1


if __name__ == "__main__":
    try:
        sys.exit(run(sys.argv[1:], os.environ))
    except Exception:
        sys.exit("C99 evidence not publishable")
