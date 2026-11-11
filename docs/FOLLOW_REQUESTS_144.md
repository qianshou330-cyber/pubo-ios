# Build 144 candidate: received and sent follow requests

Source reference: verified H5 snapshot `pages/follow-requests.vue` provides received/sent tabs, defaults unlocked accounts to sent, requires confirmation before reject/cancel, and uses separate list/sent endpoints with follower/followee records. Its shared paginator guards generations and loading.

Native changes:
- Received and sent directions; pending sent requests can be withdrawn from the list.
- Explicit keep / confirm alerts for reject and cancellation; accepting stays direct, matching H5.
- Unique read generations plus direction/account and cancellation checks. Starting a mutation invalidates outstanding list reads so old snapshots cannot resurrect handled requests. Leaving the page invalidates all reads.
- Cursor is retained from the raw last page even after removing every displayed row; the next page can still load, and empty-state only appears at known end. Non-advancing pages stop to avoid endless pagination.
- Mutation failure leaves that row disabled until an explicit successful refresh establishes its current state, rather than enabling blind resubmission.
- UI and core tests use synthetic requests; no production accounts or writes.

Tests: FollowRequestPresentationTests (pure model) and FollowRequestParityUITests (Mac only). UI tests cover confirmation keep/confirm, cancellation, tab changes with deliberately delayed stale response, and default sent tab. Compile/UI status remains pending final-commit CI. The synthetic menu navigation needs verification on both device sizes.

Remaining: contacts aggregate list and FollowList refresh/busy fixes are outside this candidate. No live private H5 screenshots acquired; do not claim full visual parity.

## Review follow-up and follow-list recovery
- Session generation is part of request context and mutation confirmations, not only user ID. Mutation tokens prevent an old completion clearing a new account's busy state.
- Request rows explicitly contain separate accessibility children and carry no parent identifier; button identifiers remain independent.
- Follow / followers list now has busy and generation guards, cancellation checks, response validation, retry mode, empty state and pull-to-refresh. Server cursor is independent of hidden/unavailable users; a non-advancing cursor stops pagination.
- New FollowListPageTests and FollowListParityUITests cover duplicate/update ordering, unavailable records, invalid-response preservation, first-load retry, last-page reachability and empty followers. Native test execution remains pending.
