# PUBO build 144 candidate

Based on build 143. Final-commit CI execution is pending; this is not a claim of passing coverage.

## Native page alignment
- Follow requests received/sent directions and unlocked-account default match the inspected H5 source.
- Explicit confirmation for rejection or withdrawal; generation/account guards protect delayed reads and mutations.
- Cursor is independent of removed or unavailable rows. Follow/follower lists now provide refresh, initial-load retry, empty and completion states without overlapping stale requests.
- SwiftUI alert test queries are scoped to a single alert and first matching action, preserving cancel/confirm assertions rather than bypassing them.

## Evidence expansion
- Existing real timeline H5 capture remains unchanged.
- A separate experimental multipage job renders actual public H5 JavaScript against local synthetic read APIs for channels, Drive, profile and privacy.
- The fixture forwards no production APIs, account credentials or mutations. Unknown API routes fail closed.
- Each page requires its own controls/data/API evidence. Diagnostics are clearly marked NOT-PARITY; any failed page fails the job. No page will be declared matched solely from a navigation label.

## Validation before push
- Python packaging tests: 6/6.
- New H5 fixture server audit: 9 HTTP/CSP assertions passed in the separate preparation workspace.
- Python/JavaScript syntax and git diff checks passed.
- Core Swift, native simulator tests, real H5 rendering and unsigned device packaging require Mac/Linux CI after push.

## Build 143 evidence-driven recovery included
- Drive confirmation queries handle SwiftUI parent/child accessibility duplication without removing either consent path.
- Reveal lazy profile media rows before querying them. The native media menu label now fills its visible row and has stable identifiers; tests explicitly wait for the menu.
- Privacy regression taps the actual UIKit switch inside its identified SwiftUI row, then checks both its value and dependent enabled state.
- Empty profile fields receive one focus tap rather than two, which triggered the system AutoFill menu in the 143 large-device recording. Exact final text is still required.
- These remedies are pending 144 Mac regression, not declared fixed solely by source changes.
