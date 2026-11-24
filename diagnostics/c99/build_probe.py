"""Temporary state-only diagnostic for one shared unsigned build, never an XCTest row."""
import json
import os
import platform
import re
import selectors
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path

BASE = "91e90c887039967594646879c6513ea16544acce"
TREE = "0849f368f6ae16ec66a4fcd95cf42933782ff6a7"
REPO = "qianshou330-cyber/pubo-ios"
REF = "refs/heads/diag-c99-native-focus"
WF = ".github/workflows/c99-native-focus.yml"
DOC = "diagnostics/c99/README.md"
ME = "diagnostics/c99/build_probe.py"
DIFF = {"M\t"+WF, "M\t"+DOC, "A\t"+ME}
# A source ID and maximum line number are derived from THESE exact public blobs.
SOURCES = {
    "App/Features/ProfileView.swift": ("APP_PROFILE", 487, "84841e78347bb4f27c9d5b687dcda212ce1cee69"),
    "App/Features/TimelineView.swift": ("APP_TIMELINE", 693, "203f03c4d2c5c8fc81f3664da0dc5ff2c392b767"),
    "App/Infrastructure/C99WorldRetryProbe.swift": ("APP_PROBE", 93, "d506d7b371ef155f60b448ae9adadc0c160bb759"),
    "App/Infrastructure/FixtureTransport.swift": ("APP_FIXTURE", 778, "9e8988d7c432b35e51f6a1fb6574f151deeb70ce"),
    "UITests/C99FriendsChildHandlesUITests.swift": ("TEST_FRIENDS", 106, "11dca45c0a1dc0ecb985f2c8168d145b21622893"),
    "UITests/C99WorldRetryUITests.swift": ("TEST_WORLD", 115, "d384ed7bb10485d9762bf3ac8efc766f726c8f1f"),
}
UNKNOWN = ("UNKNOWN", None)
HELP_CAP = 256 * 1024
CONSOLE_CAP = 32 * 1024 * 1024
RESULT_CAP = 2 * 1024 * 1024


def invoke(argv, timeout=60, cap=0):
    """Drain both streams without logging, bound retained bytes and wall time, including children."""
    deadline = time.monotonic() + timeout
    saved = bytearray()
    with subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, start_new_session=True) as child:
        try:
            with selectors.DefaultSelector() as sel:
                sel.register(child.stdout, selectors.EVENT_READ)
                while True:
                    left = deadline - time.monotonic()
                    if left <= 0 or not sel.select(left):
                        raise TimeoutError()
                    part = os.read(child.stdout.fileno(), 65536)
                    if not part:
                        break
                    if saved is not None:
                        if len(saved) + len(part) <= cap:
                            saved.extend(part)
                        else:
                            saved = None  # discard the whole truncated stream; continue draining
            rc = child.wait(timeout=max(0, deadline-time.monotonic()))
            return rc, None if saved is None else bytes(saved)
        finally:
            if sys.exc_info()[0] is not None:
                try:
                    os.killpg(child.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass


def git(*args):
    rc, output = invoke(["git", *args], cap=HELP_CAP)
    if rc or output is None:
        raise ValueError()
    return output.decode("ascii").rstrip("\n")


def preflight(head):
    if (git("rev-parse", "HEAD") != head or git("log", "-1", "--format=%P") != BASE
        or git("rev-parse", "HEAD^1^{tree}") != TREE or git("status", "--porcelain=v1", "--untracked-files=all")
        or set(git("diff", "--no-renames", "--name-status", BASE, head).splitlines()) != DIFF):
        return False
    pins = {p: a[2] for p, a in SOURCES.items()}
    pins.update({DOC: "54eba840a190de032024c2842894c1b4b2838de1",
                 "diagnostics/c99/focus.py": "e0fd085b5e71f0deba240c2f9f7bfc5676e55eef",
                 ".github/workflows/four-tabs.yml": "33762b7334f954b77c9ddedd65b4e7ff0d548447"})
    for p in {WF, DOC, ME} | set(pins):
        item = git("ls-tree", "HEAD", "--", p).split()
        if len(item) != 4 or item[:2] != ["100644", "blob"] or item[2] != pins.get(p, item[2]) or item[3] != p:
            return False
    return True


def maybe(argv, timeout, cap):
    try:
        rc, output = invoke(argv, timeout, cap)
        return output if rc == 0 else None
    except (OSError, subprocess.SubprocessError):
        return None


def flag(help_text, pat):
    return bool(help_text and re.search(pat, help_text, re.M))


def where(workspace, path, line, uri=False):
    # Never use basenames, suffixes, decoded traversal, or path normalization on incoming data.
    for f, (category, limit, _) in SOURCES.items():
        actual = workspace/f
        if path == (actual.as_uri() if uri else str(actual)) and 0 < line <= limit:
            return category, line
    return UNKNOWN


def only(locations):
    if len(locations) == 1:
        return next(iter(locations))
    kinds = {src for src, _ in locations}
    return (next(iter(kinds)), None) if len(kinds) == 1 and "UNKNOWN" not in kinds else UNKNOWN


def from_console(data, workspace):
    if not data:
        return None
    found = set()
    # Ignore source excerpts and build headlines. Only complete absolute compiler location lines qualify.
    # Bound individual matches as well as total input; do not echo the message, column, or path.
    for hit in re.finditer(rb"^(/[^\r\n\x00]{1,3072}?):([1-9][0-9]{0,7}):[1-9][0-9]{0,6}: (?:fatal )?error: [^\r\n\x00]", data, re.M):
        try:
            path = hit[1].decode("utf-8")
        except UnicodeError:
            return UNKNOWN
        loc = where(workspace, path, int(hit[2]))
        if loc == UNKNOWN or (found and next(iter(found))[0] != loc[0]):
            return UNKNOWN
        found = {only(found | {loc})}
    return only(found) if found else None


def unique(pairs):
    d = dict(pairs)
    if len(d) != len(pairs):
        raise ValueError()
    return d


def from_result(data, workspace):
    """Narrow, optional projection; None means schema unavailable, UNKNOWN is an explicit veto."""
    if not data or len(data) > RESULT_CAP:
        return None
    def bad(_):
        raise ValueError()
    try:
        obj = json.loads(data, object_pairs_hook=unique, parse_constant=bad)
        if type(obj) is not dict or obj.get("status") != "failed":
            return None
        rows, count = obj.get("errors"), obj.get("errorCount")
        if type(rows) is not list or type(count) is not int or not 1 <= count == len(rows) <= 64:
            return None
        found = set()
        for row in rows:
            if type(row) is not dict or type(row.get("sourceURL")) is not str:
                return UNKNOWN
            url, sep, frag = row["sourceURL"].partition("#")
            if len(url) > 3072 or not sep or len(frag) > 384:
                return UNKNOWN
            coords = {}
            for field in frag.split("&"):
                k, eq, val = field.partition("=")
                if (not eq or k in coords or k not in {"StartingLineNumber", "EndingLineNumber",
                    "StartingColumnNumber", "EndingColumnNumber", "CharacterRangeLen", "CharacterRangeLoc",
                    "Timestamp"} or not re.fullmatch(r"[0-9]{1,16}(?:\.[0-9]{1,12})?", val)):
                    return UNKNOWN
                coords[k] = val
            line = coords.get("StartingLineNumber", "")
            if not re.fullmatch("[1-9][0-9]{0,7}", line):
                return UNKNOWN
            found.add(where(workspace, url, int(line), uri=True))
        return only(found)
    except (TypeError, ValueError, RecursionError, UnicodeError):
        return None


def diagnostic(private, workspace, state):
    if not preflight(state["commit"]):
        return
    state["outcome"] = "HOST_UNAVAILABLE"
    version = maybe(["xcodebuild", "-version"], 60, HELP_CAP)
    if (platform.system(), platform.machine()) != ("Darwin", "x86_64") or version is None or version.strip() != b"Xcode 26.0.1\nBuild version 17A400":
        return
    state["outcome"] = "PREPARE_UNAVAILABLE"
    if not shutil.which("xcodegen") and invoke(["brew", "install", "xcodegen"], 600)[0]:
        return
    if invoke(["swift", "scripts/brand-assets.swift"], 120)[0] or invoke(["xcodegen", "generate"], 120)[0]:
        return
    state["outcome"] = "BUILD_UNAVAILABLE"
    help_text = maybe(["xcodebuild", "-help"], 30, HELP_CAP)
    bundle = private/"build.xcresult"
    if os.path.lexists(bundle):
        return
    use_bundle = flag(help_text, rb"^[ \t]*-resultBundlePath[ \t]+(?:PATH|<path>)(?:[ \t\r]|$)")
    state["bundleRequested"] = use_bundle
    args = ["xcodebuild", "-project", "PUBO.xcodeproj", "-scheme", "PUBO", "-configuration", "Debug",
            "-sdk", "iphonesimulator", "-derivedDataPath", str(private/"dd"), "-destination", "generic/platform=iOS Simulator"]
    if use_bundle:
        args += ["-resultBundlePath", str(bundle)]
    args += ["CODE_SIGNING_ALLOWED=NO", "ARCHS=x86_64", "ONLY_ACTIVE_ARCH=YES", "build-for-testing"]
    try:
        rc, console = invoke(args, 900, CONSOLE_CAP)
    except (TimeoutError, subprocess.TimeoutExpired):
        state["outcome"] = "BUILD_TIMEOUT"
        return
    state["buildExitZero"] = rc == 0
    state["outcome"] = "BUILD_ZERO_NOT_TESTED" if rc == 0 else "BUILD_NONZERO"
    if rc == 0:
        return
    plain = from_console(console, workspace)
    state["locationEvidence"] = "NONE"
    structured = None
    if use_bundle and not bundle.is_symlink() and bundle.is_dir():
        get = ["xcrun", "xcresulttool", "get", "build-results"]
        help_text = maybe(get + ["--help"], 30, HELP_CAP)
        if (flag(help_text, rb"^[ \t]*USAGE: (?:xcresulttool )?get build-results(?:[ \t\r]|$)") and
            flag(help_text, rb"^[ \t]*--path[ \t]+<path>(?:[ \t\r]|$)")):
            # Use advertised --path only; accept the default representation only if it parses as JSON.
            state["bundleReadAttempted"] = True
            structured = from_result(maybe(get + ["--path", str(bundle)], 45, RESULT_CAP), workspace)
    if structured is None and plain not in (None, UNKNOWN):
        loc, state["locationEvidence"] = plain, "CONSOLE"
    elif structured not in (None, UNKNOWN) and plain is None:
        loc, state["locationEvidence"] = structured, "RESULT"
    elif structured not in (None, UNKNOWN) and plain not in (None, UNKNOWN) and structured[0] == plain[0]:
        loc, state["locationEvidence"] = only({plain, structured}), "BOTH"
    else:
        loc = UNKNOWN
    state["source"], state["line"] = loc


def run(argv, env):
    sha, runid, attempt = (env.get(k, "") for k in ("GITHUB_SHA", "GITHUB_RUN_ID", "GITHUB_RUN_ATTEMPT"))
    if (argv or env.get("GITHUB_REPOSITORY") != REPO or env.get("GITHUB_REF") != REF
        or env.get("GITHUB_EVENT_NAME") != "push" or not re.fullmatch("[0-9a-f]{40}", sha)
        or not re.fullmatch("[1-9][0-9]{0,19}", runid) or attempt != "1"
        or Path(env["GITHUB_WORKSPACE"]) != Path.cwd()):
        return 1
    temp = Path(env["RUNNER_TEMP"])
    dest = temp/"c99-build-only"
    if not temp.is_absolute() or os.path.lexists(dest):
        return 1
    state = dict(schema=1, mode="SHARED_BUILD_ONLY", commit=sha, run=runid, attempt=attempt,
                 outcome="SOURCE_UNAVAILABLE", buildExitZero=None, source="UNKNOWN", line=None,
                 bundleRequested=False, bundleReadAttempted=False, locationEvidence="NONE",
                 nativeExitZero=None, productVerified=False, cases={}, captures={})
    with tempfile.TemporaryDirectory(dir=temp) as d:
        private = Path(d)
        try:
            diagnostic(private, Path.cwd(), state)
        except (OSError, ValueError, RecursionError, subprocess.SubprocessError):
            pass  # never serialize exception values, environment, logs or dynamic keys
        stage = private/"safe"
        stage.mkdir(mode=0o700)
        (stage/"state.json").write_text(json.dumps(state, sort_keys=True)+"\n", encoding="ascii")
        stage.rename(dest)
    with open(env["GITHUB_OUTPUT"], "a", encoding="ascii") as output:
        output.write("ready=true\n")
    return 0 if state["buildExitZero"] is True else 1


if __name__ == "__main__":
    try:
        sys.exit(run(sys.argv[1:], os.environ))
    except Exception:
        sys.exit(1)
