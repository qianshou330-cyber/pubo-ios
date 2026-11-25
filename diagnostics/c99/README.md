# PUBO C99 simulator diagnostic handoff

The public branch `diag-c99-native-focus` at
[`5f166189`](https://github.com/qianshou330-cyber/pubo-ios/commit/5f166189786cdccdcd4fd4157d8549afa3fcfa40)
contains the World empty-list Retry progress and Friends cross-site handle fixes.
It does not contain a validated simulator result or IPA.

## First run

[Run 45317478447, attempt 1](https://github.com/qianshou330-cyber/pubo-ios/actions/runs/45317478447)
ended with four failed jobs. Both Friends runner states were `SETUP_UNAVAILABLE`,
with no XCTest exit recorded. Both World runner states were `SUMMARY_REJECTED`,
with a nonzero native command exit. None of the four archives contained a
verified test case or original screenshot. The CI state does not locate the
underlying failure or establish whether either app fix works.

## Second run

[Run 45340380966, attempt 1](https://github.com/qianshou330-cyber/pubo-ios/actions/runs/45340380966)
at [864e4daa](https://github.com/qianshou330-cyber/pubo-ios/commit/864e4daace25ad3492fa8cdbde58bfa0a975d500)
ended 0/4. Both World rows and Friends on iPhone 17 recorded a nonzero combined
build/test command exit, then `SUMMARY_REJECTED` at `TIME_WINDOW`. Friends on
iPhone 17 Pro Max stopped at `SIM_BOOT_WAIT` before the combined command;
timeout versus command error is unknown. No verified cases, original screenshots,
or IPA. These receipts do not establish a compiler, launcher, XCTest or app cause.

## Next diagnostic: build first, then test without rebuilding

Only the focused driver, its workflow pin, and this handoff change. On the same
Intel runner, first run an unsigned generic Debug Simulator `build-for-testing`
with a 15-minute limit. Only after a zero exit, inventory/create/boot the exact
iOS 26.1 simulator, then run the existing method selection with
`test-without-building` and a 20-minute limit using the same private derived
data. No extra row, rerun, telemetry, raw output, or package is requested.

- `buildExitZero` is true or false only for a returned build command. A nonzero
  exit is a build-stage failure, not necessarily a Swift compiler error. At
  `BUILD_FOR_TESTING`, timeout or command unavailability leaves it null.
- A failed `SIM_BOOT_WAIT` can now distinguish `TIMEOUT` from `COMMAND_ERROR`.
  `nativeExitZero` now refers only to the test-without-building command; null
  means no exit was obtained. A zero build or test exit is not a verified row.
- The exact World/Friends cases, result-tree and summary requirements, and
  original screenshot gates are unchanged. No failed row publishes a PNG.
  Local CLI-boundary tests do not establish a real build, bundle, launch,
  simulator result or visual match.

## Third run and single-build handoff

[Run 45342259406, attempt 1](https://github.com/qianshou330-cyber/pubo-ios/actions/runs/45342259406)
at `91e90c887039967594646879c6513ea16544acce` ended 0/4. All four state-only
receipts recorded `BUILD_NONZERO` at `BUILD_FOR_TESTING`, build exit nonzero,
native exit null. The identical generic build stopped before any simulator,
selected test or screenshot. The receipts do not identify a Swift or other cause.

This temporary **one-job build-only** mode runs that unsigned Debug build once.
It creates no simulator, launches no tests, and never uploads build output,
result bundles or images. The earlier strict UI driver stays unchanged; the
normal test branch, stock workflow, app, project, and Release/IPA are untouched.
Build success means only that the build returned zero on this runner.

The receipt can identify one reported source file, not the overall root cause. `APP_PROFILE`, `APP_TIMELINE`, `APP_PROBE`, `APP_FIXTURE`,
`TEST_FRIENDS` and `TEST_WORLD` stand for the six pinned C99 Swift source files.
A line is included only for a single agreed position within that file. Reports
from more than one file or from an unapproved path do not publish a location. The build
bundle and capped console reads remain private to the runner. A missing result
bundle or unsupported tool does not justify printing logs or rerunning a matrix.

## Fourth run and targeted line handoff

[Run 45344707636, attempt 1](https://github.com/qianshou330-cyber/pubo-ios/actions/runs/45344707636)
at `387b746a7c911ce70d539a01e17d0fcaea6f4efb` completed as one build-only job
with `BUILD_NONZERO`, exact `APP_PROBE` from both accepted channels, and no line
published because there were at least two distinct accepted positions across
those channels. No precise reason, simulator, test, screenshot, or IPA.

The successor keeps that exact build command and reports independent sorted line
sets for the same pinned public 93-line source only. Each line has one fixed
conservative diagnostic class or `UNKNOWN`; no evidence is inferred from build
exit alone. Channel states distinguish no match, unavailable input and a schema
that was not recognized. The historical receipt is unchanged. These new
receipts remain build diagnostics only, never test or product verification.

## Fifth run and DEBUG fixture compile repair

[Run 45347343014, attempt 1](https://github.com/qianshou330-cyber/pubo-ios/actions/runs/45347343014)
at `3819229bbad12042dc9638cab9ae6d71f200eac8` returned `BUILD_NONZERO`. The
allowlisted console identified `TYPECHECK_COMPLEXITY` at line 76 in the pinned
DEBUG World Retry probe. The independent result location was line 75, class
`UNKNOWN`. The console line begins the nested map used to construct recovered
fixture rows. No UI test or screenshot ran.

This successor splits that DEBUG fixture into explicitly typed nonce, ID and text
values, a simple loop, and separately assigned `JSONValue` fields. It preserves
the five rows and their order, recovered receipt, response, cancellation and
phase transitions. Product views, network paths, project, stock workflows, and
native test code are unchanged.

The temporary build-only mode is replaced by the original focus: World and
Friends on iPhone 17 and iPhone 17 Pro Max, one attempt on this diagnostic
branch. Each row must first pass the same unsigned Debug build before starting
its simulator and exact methods. Original result/device/case/PNG gates remain
unchanged. No build-only outcome verifies product behavior; no Release or IPA.

## Sixth run and reduced summary-time diagnostic

[Run 45349455010, attempt 1](https://github.com/qianshou330-cyber/pubo-ios/actions/runs/45349455010)
at `c51edabe95a384de54666bd9fcfb951ae52b895a` compiled all four Debug rows.
World on iPhone 17 and Friends on both devices subsequently returned nonzero
from the native command, with `SUMMARY_REJECTED / TIME_WINDOW`. Their summary
keys were recognized, but the legacy check did not locate the type or ordering
mismatch or verify any intended test case. World on iPhone 17 Pro Max stopped
earlier at `SIM_BOOT_WAIT / TIMEOUT`. Only state receipts were verified, no
originals or IPA. This does not establish an XCTest launch or product failure.

This temporary successor executes the unchanged Friends/iPhone 17 lane once.
A state-only observer distinguishes timestamp types, numeric-zero sentinels,
ordering, and coarse offset from a paired host wall/monotonic window. It reports
only categories for summary count and presence of known planned method records.
A reported record is not proof a method body ran. An unrecognized tool output
or absent result is not inferred to mean zero tests. Offsets do not authorize
timestamp conversion for screenshot validation.

The original strict summary, case, device and image gates remain unchanged.
The diagnostic mode ends before any attachment export and cannot verify a
product row. No raw times, error messages, tool output, case names, files or
screenshots may leave the runner. Simulator boot policy and native arguments
are unchanged; the iPhone 17 Pro Max timeout remains a separate question.

## Seventh run and one stock-invocation experiment

[Run 45352573858, attempt 1](https://github.com/qianshou330-cyber/pubo-ios/actions/runs/45352573858)
at `d716b298da70ec3eebd97093188b604dd1db682d` built the Friends iPhone 17
row. Its native command returned nonzero, with equal finite summary times
near a consistent host clock, zero reported tests and no planned method
records. No case body or original image was verified. This does not locate
the failure among selection, install, launch, or result collection.

The next single Friends/iPhone 17 attempt uses the previously used C98
prebuilt-test invocation settings, retaining the two exact method selections
and the same private build, exact simulator, and strict evidence gates. It
does not rely on assumed enumeration or prebuilt manifest schemas. Several
native flags change together; a better result cannot establish which mattered.

On a nonzero native exit only, a read-only lookup reports whether the app
container is present on the job's simulator at that moment. Lookup failure
is not proof the app was never installed. No lookup output, path, raw test
result, or log is collected for publication. This is not runner-launch proof.
Only fully gated original images are eligible on a successful synthetic row.
No stock workflow, app, boot configuration, Release or IPA change.

## Eighth run and bounded failure attribution

[Run 45357210757, attempt 1](https://github.com/qianshou330-cyber/pubo-ios/actions/runs/45357210757)
at `a0954a837af3a5e68149b1cad65efa610f6740a6` built the Friends/iPhone 17 row.
Its stock native command returned nonzero. The exact device summary had finite
ascending times, a positive reported test count, and rejected the count gate.
The earlier method projection did not recognize the tree, and the app lookup
did not confirm a container. No case or original image was verified.

This observation separates total-count mismatch, invalid numeric categories,
summary/device disagreement, and arithmetic mismatch. It also distinguishes
known method records and corroborating failed-method rows from an exact
`System Failures` suite marker in the bound UI target. The marker is an Xcode
report label, not a unique error code or confirmed launch cause. A record is
not test-body proof. Only fixed categories are eligible in the state receipt.

No native command, simulator/boot, app, test, or success/evidence-gate change.
No additional provider tool call, raw diagnostics, or failure images. If the
coarse result is still inconclusive, inspect in a separately authorized macOS
environment; do not keep repeating the same hosted check.

## Ninth run and stock simulator environment alignment

[Run 45361077267, attempt 1](https://github.com/qianshou330-cyber/pubo-ios/actions/runs/45361077267)
at `211bfe9c8c36ed2e662befb5625fd7ae10db2212` compiled the Debug bundle
(`buildExitZero: true`) and then stopped in `SIM_BOOT_WAIT` (`TIMEOUT` after
240s, `status: SETUP_UNAVAILABLE`, `nativeExitZero: null`) before any test ran.

Comparing `.github/workflows/c99-native-focus.yml` and `diagnostics/c99/focus.py`
against the working `four-tabs.yml` + `scripts/simulator_boot.py` environment
identified three concrete runner-environment differences:

1. `c99-native-focus.yml` only set `DEVELOPER_DIR` without running
   `sudo xcode-select -s /Applications/Xcode_26.0.1.app/Contents/Developer`,
   which `four-tabs.yml` runs before CoreSimulator services start.
2. `c99-native-focus.yml` ran under `umask 077` while `focus.py` placed both
   `-derivedDataPath` and `-resultBundlePath` inside a `0700` temporary
   directory, matching Run 8's `appContainer: NOT_CONFIRMED` and `TEST_COUNTS`
   failure before any planned method ran.
3. `focus.py` ran a single 240s `xcrun simctl bootstatus -b` with no recovery,
   unlike `scripts/simulator_boot.py`'s 300s timeout plus bounded shutdown,
   `CoreSimulatorService` reset, and one retry.

This successor aligns ONLY those three runner-environment details (pinning
`scripts/simulator_boot.py`, running `sudo xcode-select -s`, removing
`umask 077` from build/test with ephemeral `build/c99-debug` and
`build/c99-focused.xcresult` cleaned up in `finally`) and runs the full 2x2
matrix (`small`/`large` x `friends`/`world`). All six C99 Swift source files,
all strict summary/tree/zero-warning/PNG gates, and redacted state-only failure
publication remain unchanged.

## Tenth run and closed-enum failure-reason attribution

[Run 45658803649, attempt 1](https://github.com/qianshou330-cyber/pubo-ios/actions/runs/45658803649)
at `e07d8cbbcc7f528638ad578fed986608eacdf840` resolved the runner-environment
blockers on all 4/4 jobs (`buildExitZero: true`, `appContainer: PRESENT`,
`systemFailureMarker: NOT_REPORTED`, `plannedMethods: PLANNED_METHOD_REPORTED`,
`tree: BOUND`, exact expected test counts):

- `world / large` (iPhone 17 Pro Max, iOS 26.1): **`VERIFIED_SYNTHETIC_ROW`**
  ([artifact 15045002137](https://github.com/qianshou330-cyber/pubo-ios/actions/runs/45658803649/artifacts/15045002137)),
  `runtimeWarningCount: 0`, 3 verified original PNGs (`initial-503`,
  `retry-pending`, `retry-restored`).
- `world / small` (iPhone 17), `friends / small` (iPhone 17), and
  `friends / large` (iPhone 17 Pro Max) executed their planned methods and
  recorded `FAILED_RECORD` on the planned cases.

This successor runs only the two standard-size lanes (`small/friends` and
`small/world`) and maps each matched `testFailures` entry's `failureText` to a
closed, redacted enum (`ProofError` / `C99ProbeFailure` / XCTest timeout class)
without emitting any raw text. No product, test, or evidence-gate change.
