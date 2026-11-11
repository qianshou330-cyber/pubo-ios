# Build 143 candidate: channel search and creation policy

Reference: verified 2026-10-31 H5 snapshot `packages/frontend/src/pages/channels.vue`.
- Lines 16–25 expose `nameAndDescription` and `nameOnly` search scope controls; `search()` sends `type` alongside query. Native previously had only query and could not select name-only search.
- The owned-channel section shows Create only for `$i?.policies.canCreateChannel`. Native previously always displayed Create and entered the editor regardless of this account policy.

Changes:
- Add native search scope segmented control with exact H5 API values. Query/scope context participates in stale-response rejection; requests have unique attempt IDs. Empty search shows a prompt, not an initial request or fake empty-results state.
- Hide Create channel unless the account explicitly permits it. Recheck in editor save and directly before the create mutation; channel editing is not blocked by creation policy and other collection kinds are unaffected.
- Add core tests for exact request payload and fail-closed creation policy plus local synthetic UI tests for both policy states and both search modes. UI tests never submit creation or touch production data.

Tests added: ChannelPolicyTests and ChannelParityUITests. Linux can run diff checks only for these Swift changes; compile and UI pass status must come from final-commit Mac CI.

Scope: This is not full contacts/follow-list/channel visual parity. No H5 screenshot of private channel search was acquired. The new native screenshots are evidence only until corresponding real H5 references are captured.
