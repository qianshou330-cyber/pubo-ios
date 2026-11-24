"""Temporary state-only diagnostic for one shared unsigned build, never an XCTest row."""
import hashlib
import json
import os
import platform
import re
import selectors
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time
from pathlib import Path

BASE = "387b746a7c911ce70d539a01e17d0fcaea6f4efb"
TREE = "11b15f468a1ea584e81b1ac8541f86aab14e0c1c"
REPO = "qianshou330-cyber/pubo-ios"
REF = "refs/heads/diag-c99-native-focus"
WF = ".github/workflows/c99-native-focus.yml"
DOC = "diagnostics/c99/README.md"
ME = "diagnostics/c99/build_probe.py"
DIFF = {"M\t"+WF, "M\t"+DOC, "M\t"+ME}
# A source ID and maximum line number are derived from THESE exact public blobs.
SOURCES = {
    "App/Features/ProfileView.swift": ("APP_PROFILE", 487, "84841e78347bb4f27c9d5b687dcda212ce1cee69"),
    "App/Features/TimelineView.swift": ("APP_TIMELINE", 693, "203f03c4d2c5c8fc81f3664da0dc5ff2c392b767"),
    "App/Infrastructure/C99WorldRetryProbe.swift": ("APP_PROBE", 93, "d506d7b371ef155f60b448ae9adadc0c160bb759"),
    "App/Infrastructure/FixtureTransport.swift": ("APP_FIXTURE", 778, "9e8988d7c432b35e51f6a1fb6574f151deeb70ce"),
    "UITests/C99FriendsChildHandlesUITests.swift": ("TEST_FRIENDS", 106, "11dca45c0a1dc0ecb985f2c8168d145b21622893"),
    "UITests/C99WorldRetryUITests.swift": ("TEST_WORLD", 115, "d384ed7bb10485d9762bf3ac8efc766f726c8f1f"),
}
TARGET = "App/Infrastructure/C99WorldRetryProbe.swift"
TARGET_LINE_MAX = SOURCES[TARGET][1]
CONFLICT = "UNKNOWN"
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
    pins.update({DOC: "48b221116af433f934ccccc9b014c860f2bea0f7",
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


# Deliberately no diagnostic-names flags or Swift build-setting override.
# Recognize only whole Swift message forms from upstream DiagnosticsSema.def and
# the unresolved-name regression tests; substituted names/types are never returned.
ATOM = r"'[^'\x00-\x1f\x7f]{1,160}'"
NAME = r"'[$_a-zA-Z][$_a-zA-Z0-9]{0,127}'"
OP = r"'[+*/%<>=!&|^~?-]{1,16}'"
SIGNATURES = tuple((tag, re.compile(pattern)) for tag, pattern in (
    ("NAME_LOOKUP", rf"cannot find {NAME} in scope"),
    ("MODULE_IMPORT", rf"no such module {NAME}"),
    ("MEMBER_LOOKUP", rf"(?:value of type|type) {ATOM} has no member {NAME}"),
    ("TYPE_CONVERSION", rf"cannot convert value of type {ATOM} to (?:expected argument type|specified type|closure result type) {ATOM}"),
    ("INVALID_OPERANDS", rf"binary operator {OP} cannot be applied to (?:operands of type {ATOM} and {ATOM}|two {ATOM} operands)"),
    ("AMBIGUOUS_USE", rf"ambiguous use of {NAME}"),
    ("TYPECHECK_COMPLEXITY", "the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions"),
))


def classify(message):
    if type(message) is not str or not 1 <= len(message) <= 1024:
        return CONFLICT
    flags = [tag for tag, pat in SIGNATURES if pat.fullmatch(message)]
    return flags[0] if len(flags) == 1 else CONFLICT


def exact_source(workspace):
    # Verify the checked out bytes, not just Git object metadata. No symlink or
    # alternate path is accepted. Check before and after the same build.
    f = workspace / TARGET
    try:
        if any(x.is_symlink() for x in (f, *f.parents) if x != workspace and x.is_relative_to(workspace)):
            return False
        if not stat.S_ISREG(f.lstat().st_mode):
            return False
        with f.open("rb") as reader:
            data = reader.read(16385)
    except OSError:
        return False
    return (len(data) <= 16384 and len(data.splitlines()) == TARGET_LINE_MAX
            and hashlib.sha1(f"blob {len(data)}\0".encode("ascii") + data).hexdigest() == SOURCES[TARGET][2])


def empty(status):
    return {"state": status, "lines": [], "classes": []}


def add(rows, line, tag):
    # A conflict is absorbing under either order, including a recognized and an
    # unrecognized form at the same location. At most 93 entries exist.
    old = rows.get(line, tag)
    rows[line] = old if old == tag else CONFLICT


def project(rows):
    if not rows:
        return empty("NO_MATCH")
    lines = sorted(rows)
    return {"state": "PROJECTED", "lines": lines, "classes": [rows[n] for n in lines]}


def from_console(data, workspace):
    if data is None or len(data) > CONSOLE_CAP:
        return empty("UNAVAILABLE")
    path = os.fsencode(workspace / TARGET)
    if len(path) > 3072 or b"\n" in path or b"\r" in path:
        return empty("UNRECOGNIZED")
    # Match only the literal absolute path at column zero. Bounded position
    # syntax, no source-excerpt/prefix guessing. A nonempty but oversized or
    # unfamiliar message still establishes a line, not a class.
    prefix = re.compile(rb"^" + re.escape(path) +
        rb":([1-9][0-9]{0,1}):[1-9][0-9]{0,6}: (?:fatal )?error: (?=[^\r\n\x00])", re.M)
    rows = {}
    for hit in prefix.finditer(data):
        line = int(hit[1])
        if not 1 <= line <= TARGET_LINE_MAX:
            continue
        # Bound every message read; a longer 'matching' prefix is not a class.
        end = data.find(b"\n", hit.end(), hit.end() + 1026)
        end = min(len(data), hit.end() + 1026) if end < 0 else end
        message = data[hit.end():end]
        if message.endswith(b"\r"):
            message = message[:-1]
        try:
            tag = classify(message.decode("utf-8"))
        except UnicodeError:
            tag = CONFLICT
        add(rows, line, tag)
    return project(rows)


def unique(pairs):
    d = dict(pairs)
    if len(d) != len(pairs):
        raise ValueError()
    return d


def coords_for(source_url, expected):
    url, sep, frag = source_url.partition("#")
    if not sep or url != expected or len(frag) > 384:
        return None
    coords = {}
    for field in frag.split("&"):
        k, eq, val = field.partition("=")
        if (not eq or k in coords or k not in {"StartingLineNumber", "EndingLineNumber",
            "StartingColumnNumber", "EndingColumnNumber", "CharacterRangeLen", "CharacterRangeLoc",
            "Timestamp"} or not re.fullmatch(r"[0-9]{1,16}(?:\.[0-9]{1,12})?", val)):
            return None
        coords[k] = val
    line = coords.get("StartingLineNumber", "")
    if not re.fullmatch("[1-9][0-9]?", line) or not 1 <= int(line) <= TARGET_LINE_MAX:
        return None
    return int(line)


def from_result(data, workspace):
    if data is None or len(data) > RESULT_CAP:
        return empty("UNAVAILABLE")
    def bad(_):
        raise ValueError()
    try:
        obj = json.loads(data, object_pairs_hook=unique, parse_constant=bad)
        if type(obj) is not dict or obj.get("status") != "failed":
            return empty("UNRECOGNIZED")
        rows, count = obj.get("errors"), obj.get("errorCount")
        if type(rows) is not list or type(count) is not int or not 1 <= count == len(rows) <= 512:
            return empty("UNRECOGNIZED")
        out = {}
        expected = (workspace / TARGET).as_uri()
        for row in rows:
            if type(row) is not dict:
                return empty("UNRECOGNIZED")
            url = row.get("sourceURL")
            if type(url) is not str or len(url) > 3457:
                continue
            line = coords_for(url, expected)
            if line is not None:
                add(out, line, classify(row.get("message")))
        return project(out)
    except (TypeError, ValueError, RecursionError, UnicodeError):
        return empty("UNRECOGNIZED")


def reconcile(console, result):
    # Never merge the line sets. Veto two known, conflicting categories for the
    # same line, without treating an unknown class in a different channel as
    # evidence against the independently recognized form.
    result_idx = {n:i for i,n in enumerate(result["lines"])}
    for i, n in enumerate(console["lines"]):
        if n in result_idx:
            j = result_idx[n]
            a, b = console["classes"][i], result["classes"][j]
            if a != b and CONFLICT not in (a, b):
                console["classes"][i] = result["classes"][j] = CONFLICT


def diagnostic(private, workspace, state):
    if not preflight(state["commit"]) or not exact_source(workspace):
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
    if not exact_source(workspace):
        state["diagnostics"] = {"CONSOLE": empty("SOURCE_REJECTED"), "RESULT": empty("SOURCE_REJECTED")}
        return
    plain = from_console(console, workspace)
    structured = empty("UNAVAILABLE")
    if use_bundle and not bundle.is_symlink() and bundle.is_dir():
        get = ["xcrun", "xcresulttool", "get", "build-results"]
        help_text = maybe(get + ["--help"], 30, HELP_CAP)
        if (flag(help_text, rb"^[ \t]*USAGE: (?:xcresulttool )?get build-results(?:[ \t\r]|$)") and
            flag(help_text, rb"^[ \t]*--path[ \t]+<path>(?:[ \t\r]|$)")):
            # Use advertised --path only; accept the default representation only if it parses as JSON.
            state["bundleReadAttempted"] = True
            structured = from_result(maybe(get + ["--path", str(bundle)], 45, RESULT_CAP), workspace)
    reconcile(plain, structured)
    state["diagnostics"] = {"CONSOLE": plain, "RESULT": structured}
    if plain["lines"] or structured["lines"]:
        state["source"] = "APP_PROBE"


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
    state = dict(schema=2, mode="SHARED_BUILD_ONLY", commit=sha, run=runid, attempt=attempt,
                 outcome="SOURCE_UNAVAILABLE", buildExitZero=None, source="UNKNOWN",
                 bundleRequested=False, bundleReadAttempted=False,
                 diagnostics={"CONSOLE": empty("NOT_READ"), "RESULT": empty("NOT_READ")},
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
