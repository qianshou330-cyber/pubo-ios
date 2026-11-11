# Build 141: source-based cross-page parity batch

Reference: public H5 source snapshot `pubo-home-first-visit-20261031-v4-source.tar.gz`, SHA256 a55531964027c23f29651252e534084b0ebad7ea9b56e0d161e14380d7e09a57. This is a 2026-10-31 source snapshot, not proof of current production visual identity. Public guest H5 was readable; private production pages were not authenticated. No production user data is modified by tests.

## Added / changed
- Composer: reply visibility cannot broaden parent visibility; specified recipients constrained to parent participants; saved narrower choices preserved; channel posts public and local-only. Applies on restoration, picker, send.
- Profile: distinguish follow / locked request / pending cancellation / unfollow. Re-read state before mutation and after it; uncertain results require refresh, not blind retry.
- Gallery featured/popular uses gallery/featured without unsupported pagination; clips support favorite listing.
- Private/group chat: explicit account availability/readonly policy and remote/unavailable peer restrictions; search has a genuine completed-empty state and sender/conversation labels.
- Synthetic UI scenarios and core tests cover these rules. Screenshot harness runs actual public H5 bundles with synthetic API data, prohibits production writes and fails closed on rendering errors.

## Page audit / remaining work
| Pages | Reviewed basis | This batch | Still outstanding |
|---|---|---|---|
| Local timeline, announcement, filters | H5 source + native simulator | 140 changes retained; retry button accessibility ID correction | Real device, exact current H5 comparison |
| Composer/reply | H5 source | Privacy restrictions | Full live account flow and pixel comparison |
| Profile/follow | H5 source | Pending request state | Filters, location/birthday and full profile fields |
| Galleries/clips | H5 source | Correct featured/favorites endpoints | Liked galleries mapping/cursor; full visuals |
| Chat home/private/group/search | H5 source | Eligibility and empty/search identity | Full live group flows and visuals |
| Login/signup/reset | H5 source + isolated backend contracts | Existing retained | Native real-backend UI setup timeout; no success claim |
| Settings/privacy/security | H5 source audit | No implementation this batch | Locked-dependent autoaccept, email feature gating |
| Drive/media | H5 source audit | No implementation this batch | Sensitive attachment explicit reveal/download |
| Channels/contacts/follow lists | H5 source audit | No implementation this batch | Creation policy, search mode, busy guards |
| Notifications/discovery/admin | Existing implementation only | No new parity claim | Full page-by-page reference audit |

## Validation / delivery boundaries
- Cloud Python packaging checks: 6 passed before push. Swift and UI tests require macOS CI; inspect exact commit run before calling them passed.
- Build140: unsigned package succeeded; large/small preview passed; timeline interactions 14/15 each, same older-retry test failed at button ID lookup. Actual recording confirms the bottom error/retry exists; 141 removes the overriding outer ID and retains/enhances assertions, pending CI. Isolated backend 69 API contract assertions passed, native UI preflight timed out twice. These are not passing end-to-end results.
- H5 fixture screenshots are valid only when report.success=true. Diagnostic failure images are not comparisons. Synthetic media placeholders, time and viewport differences must be stated.
- Unsigned IPA requires user signing before installation. No real device, iOS17 minimum, or upgrade validation claimed. No release, PR or main merge.
