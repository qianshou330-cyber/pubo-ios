# PUBO agent handoff

Snapshot: 2026-11-17 16:51 UTC. Refresh branch and Actions before acting; this is not a live status page.

## Repair records
Every fix or diagnostic change must follow [AGENTS.md](../AGENTS.md) and append to [FIX_LOG.md](FIX_LOG.md), including failed attempts, verification gaps and follow-up results.

## Source of truth
- Repository: https://github.com/qianshou330-cyber/pubo-ios
- Working branch: `ui-four-tabs-148-20261112`. Do not merge main or open PR/releases without separate authorization.
- Latest code revision at this snapshot: `55351e1922a1141ddc3eecd7e720f853bc4b232f` (C61).
- This handoff is a documentation-only commit after C61, with `[skip ci]` to avoid cancelling its active run. No code check is being waived. Check C61's exact SHA, not this documentation commit, for its test results.
- Active run: https://github.com/qianshou330-cyber/pubo-ios/actions/runs/44117699042
- The current C60/C61 diagnostic and contract changes are already pushed. The current working copy has no source difference from remote C61. Older experimental copies have divergent files; do not bulk-import them or overwrite current code. Their account/profile implementations and test files already exist in the current tree, sometimes with later changes. No claim is made that every historical scratch experiment belongs in the product.

## Product scope
Native SwiftUI iPhone client, iOS 17+. Approved bottom navigation: 消息 / 好友 / 世界圈 / 我的, anchored to bottom safe area, not floating. This is an approved redesign, not a requirement to reproduce old H5 navigation. World posting entry only in 世界圈; no nearby-people entry. Messages plus menu is scan / add by username, not create group. Preserve existing secondary features and account isolation.
Priorities: chat layout/input/actions parity, world-feed smoothness and video first frame. Use synthetic fixtures for tests, not production accounts or data. Do not modify production H5/backend/services. Follow README, docs/FOUR_TABS_148.md, docs/CHAT_ALIGNMENT.md and docs/PARITY_ROADMAP.md for wider scope.

## Verified and pending
- C61 core checks and H5 reference jobs succeeded. Local Python suite: 136/136; Node receipt tests: 2/2.
- C61 small presentation states: 4/4 with successful test-process exit. Large legacy regression: 5/5 with successful exit. Large chat actions job is now successful; inspect its raw log before quoting a method count.
- Failed small legacy, large video-poster and large presentation-states jobs: XCTest Accessibility initialization timeouts before scenarios, not established app defects.
- OCR still rejects 3 synthetic positive controls: DejaVuSans 3x 10pt 1, 3x 10pt 99plus, 3x 12pt 5. Preserve corpus expectations and screenshot geometry checks.
- Large navigation has failed; its newest raw failure has NOT yet been diagnosed at this snapshot.
- Small navigation/actions/layout, large composer and small composer are running. Small video and large layout are queued. Refresh jobs, as run-level status can lag.
- Candidate-package compiled simulator and device Release successfully, then upload-artifact CreateArtifact timed out after 5 attempts. No candidate artifact is present in the run listing. Do not say the IPA was delivered.
- Not fully accepted. Real iPhone install/signing/upgrade, camera, APNs, minimum iOS17 and actual scrolling/video experience remain unverified. Unsigned IPA needs signing. H5 references are source snapshots unless independently matched to current production.

## C60/C61 diagnostics
`UITests/AppNavigationUITestSupport.swift` buffers up to 16 samples of the existing window/frame/hittability reads; formatting happens after the waiter. Preserve 20s existence / 8s readiness budgets, finite positive intersecting geometry, conditional native hittability, one real tap and selected assertion. No coordinate fallback, skipping a tap merely because already selected, extra screenshot/AX query in the predicate, or relaxed gate.
C60 was blocked by old literal-source contracts. C61 updates that contract to check the equivalent cached proof and retains explicit `button.isHittable == true`. CI core checks now pass. Successful diagnostic samples exist, but prior intermittent failure root cause remains unproven.

## Checkout and tests
```sh
git clone --branch ui-four-tabs-148-20261112 https://github.com/qianshou330-cyber/pubo-ios.git
cd pubo-ios
git status --short
git log -1 --oneline
```
Inspect checkout instructions and relevant local skills before edits. Use a separate worktree; preserve uncommitted changes.

macOS with Xcode 26.0.1, Swift and xcodegen:
```sh
swift test
python3 -m unittest discover -s scripts -p 'test_*.py' -v
python3 scripts/check-chat-bubble-geometry.py
sh scripts/test-refresh-diagnostics.sh
node --test scripts/isolated/test-room-message-proof.mjs
bash scripts/check_chat_gate_macos.sh
swift scripts/brand-assets.swift
xcodegen generate
```
Open generated PUBO.xcodeproj for simulator development. Exact build-for-testing, synthetic UI selections, isolated execution, screenshot and package commands are in `.github/workflows/four-tabs.yml` and scripts; retain its gates. Current hosted jobs use macos-15-intel. Linux without Swift/Xcode can run Python/Node checks, not iOS or Darwin verification. Existing simulator recovery is bounded; do not introduce unbounded retry or inflate the 1800s test-run budget.

## Next actions
1. Refresh branch head, active work and all C61 jobs. Do not push normal code commits while this run is active: the workflow uses cancel-in-progress.
2. Read raw large-navigation failure and new readiness samples. Distinguish app assertions from query/screenshot/initialization/teardown failures. Passing method text without successful process exit is not a successful job.
3. After C61 finishes, rerun only candidate-package if still needed to recover the upload failure. Do not rebuild everything merely for artifact transfer, suppress upload failures, or claim access to expired hosted-runner files.
4. Investigate remaining reproducible failures; keep OCR controls, genuine interaction and QA gates intact. The short Intel SwiftPM probe succeeded but did not reproduce long simulator teardown hangs; do not keep rerunning it unchanged or claim a package-watcher root cause.
5. For each deliverable, provide changes, real H5/iOS comparison images, exact commit/test results and limitations. Never replace requested comparison images with a webpage or call a QA-incomplete candidate fully accepted.
