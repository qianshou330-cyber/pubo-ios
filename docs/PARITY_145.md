# PUBO 145 candidate

Not yet pushed or runtime verified.

- Contacts group/member paging now guards overlapping refresh, pagination, leave/re-entry and session generation. Failed requests preserve the last valid snapshot; retries never submit mutations. See CONTACTS_PAGING_145.md for tests and remaining gaps.
- Follow-request navigation is promoted above the long notification filter menu. Actual 144 recording showed the test dragging outside the menu dismissed it before reaching the bottom entry. The test now uses a stable visible real entry, preserving all received/sent/confirmation/race assertions.
- H5 channel search capture is scoped to the actual five-tab header structure rather than a potentially ambiguous role name. Failure diagnostics include structure only, not input values or request bodies. Real CI validation is still required.
- Actual 144 H5/privacy screenshot comparison revealed a disabled dependent switch remained visually green in native. Disabled native privacy controls now use neutral tint and secondary text while preserving their stored values and disabled semantics. No settings are written by the tests.
- Social test process has a bounded 45-minute timeout for the expanded 31 tests; the full job is still capped at 75 minutes.
- Build 144 large-device recording and synthesized touch prove the Drive file button's accessibility row was wider than its actual hit area (center x220, visible label ended x187). Expand the real label/content shape to the entire row; keep center-tap tests unchanged. This is a product touch-target fix, not a test-coordinate workaround.
