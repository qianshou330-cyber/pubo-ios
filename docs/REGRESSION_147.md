# Build 147 regression work (candidate, not acceptance)

## Verified prior run

Commit `718d5b7`, run `43119742693`, attempt 2:

- Both targeted regression suites passed 3/3: refresh, home navigation, privacy.
- Small full social 31/31, AuthStatic 9/9, baseline 45/46.
- Small baseline failure occurred before opening the chat edit screen. The recorded context menu remained visible. This is not evidence of draft loss.
- Large auto-accept draft-control assertion failed; the social invocation then timed out at 2700 seconds before completing the suite. No full pass count is available.
- Both H5 reference jobs passed. Packaging was correctly skipped by the UI gate.

## Candidate changes requiring new CI

- Stable message-action identifier and a bounded, single-tap wait for the actual context menu. Conflict/uncertain-write/draft assertions remain intact.
- Target-row concrete privacy switch lookup, preserving one-tap and all dependency assertions. The previous recording shows a correct-center tap without a state change; a fixture-only DEBUG setter log will distinguish control delivery from model update. This is a candidate, not a confirmed root-cause fix.
- Include chat and auto-accept failures in the focused gate (5 tests per size).
- Partition the existing full UI coverage into disjoint social-actions (22), social-settings (9), authentication (9), baseline (46) jobs per size. The 86 existing cases are not removed or weakened. Each shard requires its exact passing count and zero failures/skips/expected failures.
- A timeout remains a failure. IPA still requires both focused sizes and all full UI shards.
- Raw evidence is still retained in bounded, lossless parts. Reference images use isolated synthetic APIs, never production writes.

No main, PR, release, production state, or local-computer files changed. Swift/XCTest must run on macOS CI. Simulator results do not replace physical-device installation or upgrade validation.
