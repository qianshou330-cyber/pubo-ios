"""C99 reconstructed Debug Simulator evidence only. No live transport or packaging."""
import binascii
from datetime import datetime
from enum import Enum
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
import time
import zlib

BASE = "3818c9ad9ca7f0e32ecd18f3dd3e168cef641950"
BASE_TREE = "bdcc0ebad7833e32b3f5cee6bdabd95a7feca22b"
REPO = "qianshou330-cyber/pubo-ios"
REF = "refs/heads/diag-c99-native-focus"
NEW = {".github/workflows/c99-native-focus.yml", "diagnostics/c99/focus.py",
       "diagnostics/c99/README.md", "UITests/C99FriendsChildHandlesUITests.swift"}
STOCK = ".github/workflows/four-tabs.yml"
PIN = {
    STOCK: "33762b7334f954b77c9ddedd65b4e7ff0d548447",
    "scripts/simulator-tests.py": "c72a25bcf3a337b1373caccbe124a3988aad52dd",
    "scripts/simulator_boot.py": "b944ca9087861e7b8fc0431c50bbc92d788743f2",
    "project.yml": "a8380cf91b2570ddbdfc71be2c59f8192ef44244",
    "diagnostics/c99/build_probe.py": "4804020597564a0d818a41c423be50c2a0e199e4",
    "scripts/iphone_qa_matrix.py": "88542174097d774ec808e915c4ad20fdd5587e76",
    "scripts/iphone-qa-matrix.json": "d1850ade1d1b2291658f5e2332fb718282f42610",
}
SOURCE_PIN = {
    "diagnostics/c99/README.md": "0d36d59a4b99bcd23bdd222894e6fc8d7cca9041",
    "App/Features/ProfileView.swift": "84841e78347bb4f27c9d5b687dcda212ce1cee69",
    "App/Features/TimelineView.swift": "203f03c4d2c5c8fc81f3664da0dc5ff2c392b767",
    "App/Infrastructure/C99WorldRetryProbe.swift": "448b910b0fb94e37b5163cbe97144ac1c56d225c",
    "App/Infrastructure/FixtureTransport.swift": "9e8988d7c432b35e51f6a1fb6574f151deeb70ce",
    "UITests/C99FriendsChildHandlesUITests.swift": "e905bbeaa4ef7ffcbf6f65db4e35d037b69121a7",
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


class SetupPhase(Enum):
    SOURCE_PREFLIGHT = "SOURCE_PREFLIGHT"
    HOST_PREFLIGHT = "HOST_PREFLIGHT"
    QA_HELPER_LOAD = "QA_HELPER_LOAD"
    QA_MATRIX = "QA_MATRIX"
    SIM_INVENTORY = "SIM_INVENTORY"
    SIM_TEMPLATE = "SIM_TEMPLATE"
    XCODEGEN_CHECK = "XCODEGEN_CHECK"
    XCODEGEN_INSTALL = "XCODEGEN_INSTALL"
    BRAND_ASSETS = "BRAND_ASSETS"
    PROJECT_GENERATE = "PROJECT_GENERATE"
    SIM_CREATE = "SIM_CREATE"
    SIM_BOOT = "SIM_BOOT"
    SIM_BOOT_WAIT = "SIM_BOOT_WAIT"


def setup_phase(state, phase):
    state["setupPhase"] = phase.value


class SummaryPhase(Enum):
    READ = "READ"
    KEY_SHAPE = "KEY_SHAPE"
    TIME_WINDOW = "TIME_WINDOW"
    DEVICE_CONFIG = "DEVICE_CONFIG"
    TEST_COUNTS = "TEST_COUNTS"
    OUTCOME = "OUTCOME"


def summary_phase(state, phase):
    state["summaryPhase"] = phase.value


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


def preflight(head, state):
    setup_phase(state, SetupPhase.SOURCE_PREFLIGHT)
    need(textout("git", "rev-parse", "HEAD") == head and
         textout("git", "log", "-1", "--format=%P") == BASE and
         textout("git", "rev-parse", "HEAD^1^{tree}") == BASE_TREE,
         "SOURCE_REJECTED")
    # Compare tracked files, modes, changed names, and actual object identities before generating the project.
    need(not textout("git", "status", "--porcelain=v1", "--untracked-files=all"), "SOURCE_REJECTED")
    changed = set(textout("git", "diff", "--no-renames", "--name-status", BASE, head).splitlines())
    need(changed == {"M\t" + path for path in NEW}, "SOURCE_REJECTED")
    for p in NEW | set(SOURCE_PIN) | set(PIN):
        entry = textout("git", "ls-tree", head, "--", p).split()
        need(len(entry) == 4 and entry[:2] == ["100644", "blob"] and
             entry[2] == (SOURCE_PIN | PIN).get(p, entry[2]) and entry[3] == p, "SOURCE_REJECTED")
    setup_phase(state, SetupPhase.HOST_PREFLIGHT)
    need(platform.machine() == "x86_64" and platform.system() == "Darwin" and
         textout("xcodebuild", "-version") == "Xcode 26.0.1\nBuild version 17A400", "HOST_REJECTED")


def unique(pairs):
    result = dict(pairs)
    need(len(result) == len(pairs), "AMBIGUOUS_JSON")
    return result


def parse(data):
    need(len(data) <= 2_000_000, "UNSUPPORTED_SCHEMA")
    return json.loads(data, object_pairs_hook=unique, parse_constant=lambda _: need(False, "UNSUPPORTED_SCHEMA"))


def native_summary(summary, size, device, count, state):
    summary_phase(state, SummaryPhase.KEY_SHAPE)
    need(type(summary) is dict and set(summary) == {"devicesAndConfigurations", "environmentDescription", "expectedFailures", "failedTests",
                          "finishTime", "passedTests", "result", "skippedTests", "startTime", "statistics",
                          "testFailures", "title", "topInsights", "totalTestCount"}, "SUMMARY_REJECTED")
    summary_phase(state, SummaryPhase.TIME_WINDOW)
    need(all(type(summary[k]) in (int, float) and math.isfinite(summary[k]) for k in ("startTime", "finishTime"))
         and summary["startTime"] < summary["finishTime"], "SUMMARY_REJECTED")
    summary_phase(state, SummaryPhase.DEVICE_CONFIG)
    configs = summary["devicesAndConfigurations"]
    need(type(configs) is list and len(configs) == 1, "SUMMARY_REJECTED")
    row = configs[0]
    need(type(row) is dict and set(row) == {"device", "expectedFailures", "failedTests", "passedTests", "skippedTests",
                      "testPlanConfiguration"}, "SUMMARY_REJECTED")
    want = {"deviceId": device["udid"], "deviceName": device["name"], "modelName": MODEL[size],
            "osVersion": "26.1", "platform": "iOS Simulator", "architecture": "x86_64"}
    need(type(row["device"]) is dict and type(row["testPlanConfiguration"]) is dict and
         all(row["device"].get(k) == v for k, v in want.items()) and
         row["testPlanConfiguration"].get("configurationName") == CONFIG, "DEVICE_REJECTED")
    summary_phase(state, SummaryPhase.TEST_COUNTS)
    need(type(summary.get("totalTestCount")) is int and summary["totalTestCount"] == count,
         "SUMMARY_REJECTED")
    keys = ("passedTests", "failedTests", "skippedTests", "expectedFailures")
    counts = {k: row.get(k) for k in keys}
    need(all(type(v) is int and v >= 0 and type(summary.get(k)) is int and summary[k] == v
             for k, v in counts.items()) and sum(counts.values()) == count, "SUMMARY_REJECTED")
    summary_phase(state, SummaryPhase.OUTCOME)
    need(summary["result"] in ("Passed", "Failed"), "SUMMARY_REJECTED")
    state.pop("summaryPhase", None)
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


def case_state(summary, tree, size, device, expected, counts, state):
    summary_phase(state, SummaryPhase.DEVICE_CONFIG)
    row = summary["devicesAndConfigurations"][0]
    need(tree["devices"] == [row["device"]] and
         set(row["device"]) == {"architecture", "deviceId", "deviceName", "modelName", "osBuildNumber", "osVersion", "platform"} and
         tree["testPlanConfigurations"] == [row["testPlanConfiguration"]] ==
         [{"configurationId": "1", "configurationName": CONFIG}], "DEVICE_REJECTED")
    state.pop("summaryPhase", None)
    cases = case_tree(tree, expected)
    summary_phase(state, SummaryPhase.TEST_COUNTS)
    for result, key in (("Passed", "passedTests"), ("Failed", "failedTests"),
                        ("Skipped", "skippedTests"), ("Expected Failure", "expectedFailures")):
        need(sum(case["result"] == result for case in cases.values()) == counts[key], "SUMMARY_REJECTED")
    state.pop("summaryPhase", None)
    if counts["passedTests"] == len(expected):
        node = tree["testNodes"][0]
        for _ in range(3):
            need(node["result"] == "Passed", "TREE_REJECTED")
            node = node["children"][0]
        summary_phase(state, SummaryPhase.OUTCOME)
        need(summary["result"] == "Passed" and summary["testFailures"] == [], "SUMMARY_REJECTED")
        state.pop("summaryPhase", None)
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


def boot_helper():
    spec = importlib.util.spec_from_file_location("pubo_c99_boot", "scripts/simulator_boot.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


TIME_MODE = "SUMMARY_TIME_DIAGNOSTIC"
MISSING = object()
# A timestamp-shaped string is only a diagnostic type, not an accepted input to
# the legacy gate. Explicit timezone and bounded fractions only.
RFC = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]{1,6})?(?:Z|[+-](?:[01][0-9]|2[0-3]):[0-5][0-9])")
DECIMAL = re.compile(r"[+-]?[0-9]{1,17}(?:\.[0-9]{1,9})?")


def observed_time(value):
    if value is MISSING:
        return "MISSING", None, None
    if value is None:
        return "NULL", None, None
    if type(value) is bool:
        return "BOOLEAN", None, None
    if type(value) in (int, float):
        try:
            if math.isfinite(value):
                return ("ZERO_NUMBER" if value == 0 else "NUMBER"), value, "EPOCH_NUMBER"
        except (ValueError, OverflowError):
            pass
        return "OUT_OF_RANGE_NUMBER", None, None
    if type(value) is str:
        if len(value) <= 35 and RFC.fullmatch(value):
            try:
                return "RFC3339_TEXT", datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp(), "RFC3339"
            except (ValueError, OverflowError, OSError):
                pass
        if len(value) <= 28 and DECIMAL.fullmatch(value):
            return "NUMERIC_TEXT", None, None
        return "OTHER_TEXT", None, None
    return "OTHER_TYPE", None, None


def clock_sample():
    return time.time(), time.monotonic()


def summary_time_diagnostic(summary, before, after):
    s = summary if type(summary) is dict else {}
    kinds, values, basis = zip(*(observed_time(s.get(key, MISSING)) for key in ("startTime", "finishTime")))
    a, b = values
    order = "UNKNOWN"
    if a is not None and b is not None and basis[0] == basis[1]:
        order = "ASCENDING" if a < b else "EQUAL" if a == b else "DESCENDING"
    w0, m0 = before
    w1, m1 = after
    clock_ok = (all(math.isfinite(x) for x in (*before, *after)) and
                w1 >= w0 and m1 >= m0 and abs((w1-w0)-(m1-m0)) <= 2)
    def offset(value, kind):
        if not clock_ok or value is None or kind == "ZERO_NUMBER":
            return "UNKNOWN"
        return "BEFORE" if value < w0-60 else "AFTER" if value > w1+60 else "NEAR"
    count = s.get("totalTestCount")
    count_status = "UNKNOWN"
    if type(count) is int and count >= 0:
        count_status = "ZERO_REPORTED" if count == 0 else "POSITIVE_REPORTED"
    return dict(startType=kinds[0], finishType=kinds[1], order=order,
                clock="CONSISTENT" if clock_ok else "UNSTABLE",
                startOffset=offset(a, kinds[0]), finishOffset=offset(b, kinds[1]),
                summaryReportedCount=count_status, plannedMethods="UNAVAILABLE")


def planned_method_presence(tree, expected):
    # Independent shape-only opinion when the time gate can't read case state.
    # Never return a result enum, issue text, device name or identifier.
    if (type(tree) is not dict or set(tree) != {"testNodes", "devices", "testPlanConfigurations"}
        or type(tree["devices"]) is not list or type(tree["testPlanConfigurations"]) is not list):
        return "UNRECOGNIZED"
    klass = next(iter(expected)).split("/")[0]
    nodes = tree["testNodes"]
    for kind, name, uri in (("Test Plan", "PUBO", None), ("UI test bundle", "PUBOUITests", URL.rstrip("/")),
                            ("Test Suite", klass, URL+klass)):
        if type(nodes) is not list or len(nodes) > 1:
            return "UNRECOGNIZED"
        if not nodes:
            return "NONE_REPORTED"
        node = nodes[0]
        if (type(node) is not dict or node.get("nodeType") != kind or node.get("name") != name
            or (uri and node.get("nodeIdentifierURL") != uri)):
            return "UNRECOGNIZED"
        nodes = node.get("children")
    if type(nodes) is not list or len(nodes) > len(expected):
        return "UNRECOGNIZED"
    seen = set()
    for node in nodes:
        if type(node) is not dict or node.get("nodeType") != "Test Case":
            return "UNRECOGNIZED"
        ident = node.get("nodeIdentifier")
        if (type(ident) is not str or ident not in expected or ident in seen
            or node.get("name") != ident.split("/")[1] or node.get("nodeIdentifierURL") != URL+ident[:-2]):
            return "UNRECOGNIZED"
        seen.add(ident)
    return "PLANNED_METHOD_REPORTED" if seen else "NONE_REPORTED"


COUNT_KEYS = ("passedTests", "failedTests", "skippedTests", "expectedFailures")
RECORD_KIND = {"Passed":"PASSED_RECORD", "Failed":"FAILED_RECORD", "Skipped":"SKIPPED_RECORD",
               "Expected Failure":"EXPECTED_FAILURE_RECORD"}
ROLES = {FOLLOWING: "following", FOLLOWERS: "followers", WORLD: "worldRetry"}


def count_provenance(summary, want):
    # Called only after the exact summary/device prefix of the existing gate.
    total = summary.get("totalTestCount")
    valid_total = type(total) is int and total >= 0
    total_relation = ("INVALID" if not valid_total else "FEWER" if total < want
                      else "MORE" if total > want else "EXPECTED")
    row = summary["devicesAndConfigurations"][0]
    top = [summary.get(k) for k in COUNT_KEYS]
    local = [row.get(k) for k in COUNT_KEYS]
    valid_buckets = all(type(n) is int and n >= 0 for n in (*top, *local))
    return dict(totalRelation=total_relation,
                bucketAgreement=("INVALID_BUCKET" if not valid_buckets else
                                 "AGREES" if top == local else "DEVICE_DISAGREES"),
                bucketSum=("UNKNOWN" if not valid_buckets or not valid_total else
                           "AGREES" if sum(local) == total else "SUM_DISAGREES"))


def classify_failure_text(text):
    # Closed-enum classification only; never emit raw failureText.
    if type(text) is not str:
        return "OTHER"
    rules = (
        ("PROOF_WRONG_ROUTE", ("wrongRoute", "ProofError error 0")),
        ("PROOF_AMBIGUOUS_LIST", ("ambiguousList", "ProofError error 1")),
        ("PROOF_INVALID_GEOMETRY", ("invalidGeometry", "ProofError error 2")),
        ("PROOF_WRONG_ROWS", ("wrongRows", "ProofError error 3")),
        ("PROOF_AMBIGUOUS_ROW", ("ambiguousRow", "ProofError error 4")),
        ("PROOF_WRONG_TEXT", ("wrongText", "ProofError error 5")),
        ("PROOF_CHANGED", ("changed", "ProofError error 6")),
        ("WORLD_EXPECTED_TAB", ("expected selected World tab",)),
        ("WORLD_EXPECTED_RECOMMENDED", ("expected selected Recommended feed",)),
        ("WORLD_UNEXPECTED_FOLLOWING", ("unexpected Following selection",)),
        ("WORLD_SINGLE_SCROLL", ("expected a single timeline.scroll",)),
        ("WORLD_FALSE_EMPTY", ("false empty",)),
        ("WORLD_MISSING_503_OR_STALE", ("missing scoped first 503",)),
        ("WORLD_HELD_MISMATCH", ("held request shows old error",)),
        ("WORLD_RECOVERED_MISMATCH", ("no current-run Local recovery row",)),
        ("WORLD_RETRY_UNAVAILABLE", ("real initial Retry unavailable",)),
        ("WORLD_NO_PENDING", ("no pending state",)),
        ("WORLD_TRANSPORT_UNOBSERVED", ("transport did not observe",)),
        ("WORLD_RECOVERY_ROW_ABSENT", ("unique recovery row absent",)),
        ("WORLD_STAGE_MISMATCH", ("transport stage expected",)),
        ("WORLD_LATCH_ERROR", ("register phase", "register release", "init phase", "init release")),
        ("WORLD_PROBE_ERROR", ("C99ProbeFailure",)),
        ("XCTEST_SNAPSHOT_TIMEOUT", ("Timed out while evaluating UI query",)),
        ("XCTEST_AX_TIMEOUT", ("AX loaded notification",)),
        ("XCTEST_HITTABILITY", ("Failed to determine hittability",)),
        ("XCTEST_TAP_FOLLOWING", ("friends.following",)),
        ("XCTEST_TAP_FOLLOWERS", ("friends.followers",)),
        ("XCTEST_TAB_FRIENDS", ("app.tab.friends", "好友")),
        ("XCTEST_TAB_WORLD", ("app.tab.world", "世界圈")),
        ("XCTEST_ASSERT_EQUAL", ("XCTAssertEqual failed",)),
        ("XCTEST_ASSERT_TRUE", ("XCTAssertTrue failed",)),
    )
    for label, needles in rules:
        if any(n in text for n in needles):
            return label
    return "OTHER"


def failed_role_rows(summary, expected):
    # Actual older PUBO XCResult summaries use these six fields. Only the exact
    # test identifier, method and URI combination may attribute to either role.
    role_names = [ROLES[m] for m in expected]
    unknown = {role: "UNKNOWN" for role in role_names}
    items = summary.get("testFailures")
    fields = {"failureText", "targetName", "testIdentifier", "testIdentifierString", "testIdentifierURL", "testName"}
    if type(items) is not list or len(items) > 64:
        return unknown
    result = {role: "NOT_REPORTED" for role in role_names}
    for item in items:
        if (type(item) is not dict or set(item) != fields
            or item["targetName"] != "PUBOUITests" or type(item["testIdentifier"]) is not int
            or type(item["failureText"]) is not str):
            return unknown
        ident = item["testIdentifierString"]
        if (type(ident) is not str or not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]{0,127}/[A-Za-z_][A-Za-z0-9_]{0,127}\(\)", ident)
            or item["testName"] != ident.split("/")[1] or item["testIdentifierURL"] != URL+ident[:-2]):
            return unknown
        if ident in expected:
            result[ROLES[ident]] = "MATCHED:" + classify_failure_text(item["failureText"])
    return result


def bound_tree_provenance(summary, tree, expected):
    role_names = [ROLES[m] for m in expected]
    blank = dict(tree="UNRECOGNIZED", systemFailureMarker="UNKNOWN", extraCases="UNKNOWN",
                 **{role: "UNKNOWN" for role in role_names})
    if tree is MISSING:
        return blank | {"tree":"UNAVAILABLE"}
    row = summary["devicesAndConfigurations"][0]
    if (type(tree) is not dict or set(tree) != {"testNodes", "devices", "testPlanConfigurations"}
        or tree["devices"] != [row["device"]]
        or tree["testPlanConfigurations"] != [row["testPlanConfiguration"]]
        or tree["testPlanConfigurations"] != [{"configurationId": "1", "configurationName": CONFIG}]):
        return blank
    def one(nodes, kind, name, uri=None):
        if (type(nodes) is not list or len(nodes) != 1 or type(nodes[0]) is not dict or
            nodes[0].get("nodeType") != kind or nodes[0].get("name") != name or
            (uri is not None and nodes[0].get("nodeIdentifierURL") != uri)):
            return None
        return nodes[0].get("children")
    if tree["testNodes"] == []:
        return dict(tree="BOUND", systemFailureMarker="NOT_REPORTED", extraCases="NOT_REPORTED",
                    **{role: "NOT_REPORTED" for role in role_names})
    top = one(tree["testNodes"], "Test Plan", "PUBO")
    suites = one(top, "UI test bundle", "PUBOUITests", URL.rstrip("/"))
    if type(suites) is not list or len(suites) > 32:
        return blank
    records = {r:"NOT_REPORTED" for r in role_names}
    seen = set()
    saw_class, saw_system, saw_extra = False, False, False
    class_name = next(iter(expected)).split("/")[0]
    for suite in suites:
        if type(suite) is not dict or suite.get("nodeType") != "Test Suite":
            return blank
        name = suite.get("name")
        if name == "System Failures":
            # Apple's producer uses a normal Test Suite with this fixed label;
            # these pinned test sources do not define a suite by that name.
            if saw_system:
                return blank
            saw_system = True
            continue
        leaves = suite.get("children")
        if type(name) is not str or type(leaves) is not list or len(leaves) > 64:
            return blank
        wanted = name == class_name
        if wanted:
            if saw_class or suite.get("nodeIdentifierURL") != URL+class_name:
                return blank
            saw_class = True
        for leaf in leaves:
            if type(leaf) is not dict or leaf.get("nodeType") != "Test Case":
                return blank
            ident = leaf.get("nodeIdentifier")
            status = leaf.get("result")
            if (type(ident) is not str or not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]{0,127}/[A-Za-z_][A-Za-z0-9_]{0,127}\(\)", ident)
                or ident in seen or ident.split("/")[0] != name or leaf.get("name") != ident.split("/")[1]
                or leaf.get("nodeIdentifierURL") != URL+ident[:-2]
                or type(status) is not str or status not in RECORD_KIND):
                return blank
            seen.add(ident)
            if wanted and ident in expected:
                records[ROLES[ident]] = RECORD_KIND[status]
            else:
                saw_extra = True
    return dict(tree="BOUND", systemFailureMarker="PRESENT" if saw_system else "NOT_REPORTED",
                extraCases="PRESENT" if saw_extra else "NOT_REPORTED", **records)


STOCK_MODE = "C99_STOCK_ENV_FOCUS"


def stock_test_argv(dd_path, identifier, result, expected):
    # Match four-tabs.yml / simulator-tests.py prebuilt launch context.
    return ["xcodebuild", "-project", "PUBO.xcodeproj", "-scheme", "PUBO", "-configuration", "Debug",
            "-destination", "platform=iOS Simulator,id="+identifier, "-destination-timeout", "90",
            "-derivedDataPath", str(dd_path), "-resultBundlePath", str(result),
            "-parallel-testing-enabled", "NO"] + [
                "-only-testing:PUBOUITests/"+method[:-2] for method in expected
            ] + ["CODE_SIGNING_ALLOWED=NO", "test-without-building"]


def app_container_presence(identifier):
    # Use the exact fresh device and the app bundle pinned by project.yml.
    # No capture: paths and tool errors go to /dev/null. Nonzero is not
    # evidence of absence; the runtime may already have cleaned up the app.
    if type(identifier) is not str or not re.fullmatch(UUID, identifier):
        return "NOT_CONFIRMED"
    try:
        rc = command(["xcrun", "simctl", "get_app_container", identifier, "com.bolubo.native", "app"],
                     15, check=False).returncode
    except (OSError, subprocess.SubprocessError):
        return "NOT_CONFIRMED"
    return "PRESENT" if rc == 0 else "NOT_CONFIRMED"


def native(private, state, size, area, summary_only=False, stock_focus=False):
    expected = EXPECTED[area]
    state["status"] = "SETUP_UNAVAILABLE"
    preflight(state["commit"], state)
    setup_phase(state, SetupPhase.QA_HELPER_LOAD)
    qa = qa_helper()
    sim_boot = boot_helper()
    setup_phase(state, SetupPhase.QA_MATRIX)
    need(qa.RUNTIME == RUNTIME and qa.MATRIX[size]["model"] == MODEL[size]
         and tuple(3*qa.MATRIX[size][k] for k in ("width", "height")) == DIMS[size], "DEVICE_REJECTED")
    setup_phase(state, SetupPhase.XCODEGEN_CHECK)
    if not shutil.which("xcodegen"):
        setup_phase(state, SetupPhase.XCODEGEN_INSTALL)
        command(["brew", "install", "xcodegen"], 600)
    setup_phase(state, SetupPhase.BRAND_ASSETS)
    command(["swift", "scripts/brand-assets.swift"], 120)
    setup_phase(state, SetupPhase.PROJECT_GENERATE)
    command(["xcodegen", "generate"], 120)
    # Stock unsigned Debug build-for-testing in normal-permission build/c99-work (cleaned in finally).
    work_root = Path("build/c99-work").resolve()
    shutil.rmtree(work_root, ignore_errors=True)
    dd_path = work_root / "debug"
    dd_path.mkdir(parents=True, exist_ok=True)
    identifier = None
    try:
        state.pop("setupPhase", None)
        state["status"] = "BUILD_UNAVAILABLE"
        state["buildPhase"] = "BUILD_FOR_TESTING"
        shared = ["xcodebuild", "-project", "PUBO.xcodeproj", "-scheme", "PUBO", "-configuration", "Debug",
                  "-sdk", "iphonesimulator", "-derivedDataPath", str(dd_path)]
        try:
            rc = command(shared + ["-destination", "generic/platform=iOS Simulator", "CODE_SIGNING_ALLOWED=NO",
                                   "ARCHS=x86_64", "ONLY_ACTIVE_ARCH=YES", "build-for-testing"],
                         900, check=False).returncode
        except subprocess.TimeoutExpired:
            raise Reject("BUILD_TIMEOUT") from None
        state["buildExitZero"] = rc == 0
        need(rc == 0, "BUILD_NONZERO")
        state.pop("buildPhase")
        state["status"] = "SETUP_UNAVAILABLE"
        setup_phase(state, SetupPhase.SIM_INVENTORY)
        inventory = qa.available_inventory()
        setup_phase(state, SetupPhase.SIM_TEMPLATE)
        template = qa.select_template(inventory, size)
        name = "C99 " + MODEL[size]
        setup_phase(state, SetupPhase.SIM_CREATE)
        device = qa.create_device(size, template, name)
        identifier = device["udid"]
        setup_phase(state, SetupPhase.SIM_BOOT_WAIT)
        try:
            sim_boot.boot(identifier, private / "boot.json")
        except subprocess.TimeoutExpired:
            state["bootWaitFailure"] = "TIMEOUT"
            raise
        except (OSError, subprocess.CalledProcessError):
            state["bootWaitFailure"] = "COMMAND_ERROR"
            raise
        result = work_root / "focused.xcresult"
        state.pop("setupPhase", None)
        state["status"] = "NATIVE_UNAVAILABLE"
        if stock_focus:
            args = stock_test_argv(dd_path, identifier, result, expected)
        else:
            args = shared + ["-destination", "platform=iOS Simulator,id="+identifier, "-resultBundlePath", str(result),
                    "-parallel-testing-enabled", "NO", "-test-iterations", "1"]
            args += ["-only-testing:PUBOUITests/"+method[:-2] for method in expected]
            args += ["CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO", "ARCHS=x86_64",
                     "ONLY_ACTIVE_ARCH=YES", "test-without-building"]
        before = clock_sample() if summary_only or stock_focus else None
        rc = command(args, 1200, check=False).returncode
        after = clock_sample() if summary_only or stock_focus else None
        state["nativeExitZero"] = rc == 0
        state["status"] = "RESULT_UNAVAILABLE"
        def result_json(kind):
            return parse(command(["xcrun", "xcresulttool", "get", "test-results", kind,
                                  "--path", str(result)], 90, capture=True).stdout)
        summary_phase(state, SummaryPhase.READ)
        if stock_focus and rc != 0:
            state["appContainer"] = app_container_presence(identifier)
        if summary_only or (stock_focus and rc != 0):
            errors = (OSError, ValueError, TypeError, OverflowError, RecursionError, subprocess.SubprocessError)
            summary = MISSING
            try:
                summary = result_json("summary")
            except errors:
                pass
            observation = summary_time_diagnostic(summary, before, after)
            observation["summaryAvailability"] = ("UNAVAILABLE" if summary is MISSING else
                                                   "OBJECT" if type(summary) is dict else "OTHER_TYPE")
            tree = MISSING
            try:
                tree = result_json("tests")
                observation["plannedMethods"] = planned_method_presence(tree, expected)
            except errors:
                pass
            state["summaryDiagnostic"] = observation
            if summary is MISSING:
                raise Reject("RESULT_UNAVAILABLE")
            try:
                native_summary(summary, size, device, len(expected), state)
            except OverflowError:
                raise Reject("SUMMARY_REJECTED") from None
            finally:
                # These phases prove the existing exact summary/device prefix;
                # do not project case/issue hints for a misbound result.
                if stock_focus and state.get("summaryPhase") in (None, "TEST_COUNTS", "OUTCOME"):
                    state["failureDiagnostic"] = {
                        "count": count_provenance(summary, len(expected)),
                        "tree": bound_tree_provenance(summary, tree, expected),
                        "summaryFailureRows": failed_role_rows(summary, expected),
                    }
            raise Reject("SUMMARY_DIAGNOSTIC_ONLY" if rc == 0 else "NATIVE_NONZERO")
        summary = result_json("summary")
        counts = native_summary(summary, size, device, len(expected), state)
        state["cases"] = case_state(summary, result_json("tests"), size, device, expected, counts, state)
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
        if identifier is not None:
            for verb in ("shutdown", "delete"):
                try:
                    command(["xcrun", "simctl", verb, identifier], 30, check=False)
                except (OSError, subprocess.TimeoutExpired):
                    pass
        shutil.rmtree(work_root, ignore_errors=True)


def run(args, env, runner=native, summary_only=False, stock_focus=False):
    size, area = args
    if summary_only:
        need((size, area) == ("small", "friends") and not stock_focus, "CONTEXT_REJECTED")
    head, run_id, attempt = env["GITHUB_SHA"], env["GITHUB_RUN_ID"], env["GITHUB_RUN_ATTEMPT"]
    need(size in DIMS and area in EXPECTED and env.get("GITHUB_REPOSITORY") == REPO
         and env.get("GITHUB_REF") == REF and env.get("GITHUB_EVENT_NAME") == "push"
         and re.fullmatch("[0-9a-f]{40}", head) and re.fullmatch("[1-9][0-9]{0,19}", run_id)
         and attempt == "1", "CONTEXT_REJECTED")
    base = Path(env["RUNNER_TEMP"])
    destination = base/"c99-publish"
    need(not os.path.lexists(destination), "DESTINATION_EXISTS")
    state = dict(schema=1, commit=head, run=run_id, attempt=attempt, area=area,
                 model=MODEL[size], os="26.1", xcodePin="26.0.1/17A400", cases={},
                 status="UNAVAILABLE", buildExitZero=None, nativeExitZero=None, captures={})
    if summary_only:
        state["mode"] = TIME_MODE
    if stock_focus:
        state["mode"] = STOCK_MODE
    with tempfile.TemporaryDirectory(dir=base) as tmp:
        private = Path(tmp)
        stage = private/"safe"
        stage.mkdir(mode=0o700)
        try:
            if summary_only:
                runner(private, state, size, area, summary_only=True)
                captures = {}  # no result from this mode can enter the image path
            elif stock_focus:
                captures = runner(private, state, size, area, stock_focus=True)
            else:
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
        sys.exit(run(sys.argv[1:], os.environ, stock_focus=True))
    except Exception:
        sys.exit("C99 evidence not publishable")
