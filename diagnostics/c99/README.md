# PUBO C99 simulator diagnostic handoff

The public branch `diag-c99-native-focus` at
[`5f166189`](https://github.com/qianshou330-cyber/pubo-ios/commit/5f166189786cdccdcd4fd4157d8549afa3fcfa40)
contains the World empty-list Retry progress and Friends cross-site handle fixes.
It does not contain a validated simulator result or IPA.

## Actual result

[Run 45317478447, attempt 1](https://github.com/qianshou330-cyber/pubo-ios/actions/runs/45317478447)
ended with four failed jobs. Both Friends runner states were `SETUP_UNAVAILABLE`,
with no XCTest exit recorded. Both World runner states were `SUMMARY_REJECTED`,
with a nonzero native command exit. None of the four archives contained a
verified test case or original screenshot. The CI state does not locate the
underlying failure or establish whether either app fix works.

## Follow-through

This diagnostic-only successor adds fixed setup and result-summary phase codes.
The native exit and strict screenshot acceptance are unchanged. No raw logs,
summary payloads, device identifiers, or screenshots from failed rows are
published. A future separately authorized run remains limited to World and
Friends on iPhone 17 and iPhone 17 Pro Max simulators (iOS 26.1). Read the row
status and phase first; don't infer a case result from a failed summary. The
successor itself has not run on macOS/Xcode and must not be treated as tested.
No changes belong on the original test branch or main as part of this draft.
