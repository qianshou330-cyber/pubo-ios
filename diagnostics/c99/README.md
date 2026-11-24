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
