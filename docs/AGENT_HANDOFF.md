## C65 — 2026-11-18 06:16 UTC — bounded startup/main-layout diagnostics, NOT a product fix
- Starting from a2710b438e6f040c632470be10c77bc78a596bd4, inspected AppSession construction, PUBOApp task/scene lifecycle, BottomTabBarInset and native UI readiness helper. Construction performs synchronous fixture store/cache setup; later startup uses awaited fixture install. Existing logs cannot attribute the cold-entry 7.25s AX window query to either work, so no production behavior change is justified.
- Changes: new App/Infrastructure/StartupAccessibilityDiagnostics.swift; DEBUG hooks in App/Infrastructure/AppSession.swift and App/PUBOApp.swift; background-only modifier in App/Components/BottomTabBar.swift; states-only export in scripts/simulator-tests.py; source contracts in scripts/test_startup_accessibility_diagnostics.py.
- Enabled only with DEBUG, --ui-testing, --chat-load-fail-once and no --isolated-backend. Record session init/start return, scene lifecycle, global BAR-container geometry (not button AX geometry), PID/monotonic uptime, and MainActor scheduling intervals. At most one 60-tick/1-second sampling task per process, independent of session.start(), no UI state changes, cancellation exits immediately. Total cap128, layout cap32, reserved terminal capacity. No account/message/credential data. The transparent background cannot receive touches or become an AX element.
- Collector uses existing task-owned simulator and subsystem-filtered 1-hour retention window, covering original 30-minute UI budget plus export. Exit status and missing marker remain INCOMPLETE; neither layout nor scheduling samples satisfy acceptance. MainActor gaps can include host scheduling/suspension, and missing logs can mean cancellation/process termination or collection failure, not necessarily main-thread blocking. Instrumentation can mildly perturb scheduling; do not claim zero-impact reproduction.
- Original UI test source, 20-second existence / 8-second readiness / actual click and selection assertion, 15-second recovery, fixture responses, OCR and workflow concurrency untouched. No warm-up launch, reordered cases, fake frame, cached geometry or threshold changes. Normal full CI required; code does not use skip ci.
- Local passed: Python147/147, Node2/2, Python compilation, diff check. Swift/Xcode unavailable here, actual native compilation and simulator validation pending. Code reviewed for MainActor ownership, bounded/cancellable sampling and passive geometry; do not treat source contracts as runtime proof.
- Next: align failed AX query UTC intervals with same-process pulse/scene/layout records. Normal pulses plus valid app layout during a failed query narrow the fault toward accessibility snapshot/query handling; long pulse gaps require further host/app evidence. C63 retry root cause and overall acceptance remain unresolved.

### Read-only startup accessibility audit — 2026-11-18 04:53 UTC
- Refreshed branch at 6fa205c5fce201059c569753fbf286081fc7b6d3; latest runs are completed. Compared original C64 large attempt-3 and small attempt-2 logs, current AppNavigationUITestSupport/BottomTabBar sources, and original boot/environment receipts. No code patch or new CI execution was justified or started.
- Large attempt-3 first launch: window-frame query 7.254364 s; following button-frame query 0.004612 s returned zero rect; native hittability deliberately not queried because geometry invalid. Predicate begins about 1.003 s into unchanged 8 s wait, so one remote query consumes the remaining budget. This is query latency, not evidence that the 56pt touch target is too small.
- Same large job's SIX later launches: all single-sample readiness passes, window queries 0.0178–0.0232 s, button frames consistently (0,866,110,56), native hittable=true followed by actual tap and selected assertion. Small retry's EIGHT samples also passed, window queries 0.0186–0.0613 s, frames (0,611,94,56), true hittability. This establishes observed first-launch concentration in this job, NOT a universal first-launch defect or simulator-only cause.
- Both task-owned simulator boot receipts report READY on first boot attempt. Large environment: iPhone 17 Pro Max, iOS-26-1 runtime, x86_64, Xcode 26.0.1 (17A400). Successful simctl bootstatus did not establish app accessibility readiness. Startup AX errors in other C64 shards reinforce the investigation priority but do not prove causality.
- Source review: tabs are real Button controls, minHeight44 plus vertical padding, plain style and explicit rectangular contentShape; badges disable hit testing. Existing geometry/intersection guard precedes isHittable; selected assertion follows actual tap. No demonstrated layout or hit-target defect supports changing these controls. Conversation suppression begins only in destination onAppear; this failed sample occurred before conversation navigation.
- Keep threshold, order and controls unchanged. Do NOT cache a previous valid frame, trust screenshot geometry instead of AX, skip the initial tab tap, add a warm-up launch, reorder cases, or extend timeout to turn the observation into a pass. Such changes would obscure the failed cold entry.
- Next evidence needed before product repair: synchronized app-side main-thread/layout lifecycle timing versus native AX query timing during a failing first launch, plus runner/system responsiveness. Any added observation must stay synthetic-only, avoid extra synchronous AX calls within the readiness budget, and preserve original failed outcome. Existing evidence cannot distinguish stale AX snapshot, snapshot service stall, or main-thread responsiveness. No claim of root cause or fix; C64 remains incomplete.

### C64 large states retry failed before recovery — 2026-11-18 04:05 UTC
- Attempt 3 job 134555169924 completed failure: 4 methods, 3 passed. Loading/empty, link-preview retry and sender-name preference passed. Explicit retry-recovery failed at initial messages-tab readiness (ChatComposerParityUITests.swift:14), before tab tap, conversation navigation or retry.
- Original readiness sample: one evaluation; window query took 7.254364 seconds, window 440x956, returned tab frame (0,0,0,0), framePositive=false/intersects=false; hittability correctly not queried. Existing 8-second readiness budget expired. This is a real failed readiness gate; do not substitute visible pixels for usable accessibility geometry or increase the budget.
- Downloaded artifact 14395159445. Stage capture INCOMPLETE, zero events, collection exit 0. Original failure recording 5CDB145A-CD8E-42CB-AB6F-4E08E19436F6.mp4 inspected near its end: message list/tab bar visible, no private-chat/retry screen. Query debug attachment contains only the query chain, not a full AX hierarchy. Visual presence with returned zero frame does not prove hittability or identify a product root cause.
- Both isolated states retries have now ended; no active job in current run. Small states retains its single 4/4 pass and complete 18-event lifecycle from attempt 2; large recovery remains untested beyond entry readiness. No new product fix or another blind rerun was made. Earlier failed attempts remain preserved.
- Next investigation should target startup accessibility readiness/snapshot latency before retry logic: compare first-launch and subsequent-launch query timings, retain actual window/frame/hit requirements, collect evidence without changing test order or filtering the failing case. C63 persistent-spinner hypothesis remains unconfirmed. Overall C64 still fails; not release acceptance.

### C64 small states recovery verified once; large retry — 2026-11-18 03:30 UTC
- Same code 236cc491176045e72f992e3a64f39a7d6047f013; attempt 2 small-states job 134539167538 succeeded. Raw log verifies 4/4: explicit failure/retry recovery, loading/empty, link-preview retry, sender-name preference. Genuine chat.retry tap at 03:02:37 and room.retry at 03:04:23; existing assertions/timeouts unchanged.
- Downloaded artifact 14393603421 (do not confuse with failed attempt-1 artifact 14385955493). chatload capture CAPTURED, exit 0, 18 events. Private first request entered 03:02:30.902, failed once after delay at 03:02:36.101, exited with errorPresent=true/loading=false. Retry entered 03:02:38.073; second transport returned at 03:02:43.144; timeline-return 03:02:43.741; published 03:02:43.769 with count=2/loaded=true/current=true/cancelled=false; load-exit loading=false/errorPresent=false. No state batches were needed in this fixture path. This proves one successful recovery lifecycle, not the cause of earlier stalls.
- Inspected original recovered private PNG 4772FDE9-73F3-4A3F-B836-AE4F9EA5408D.png and room PNG FAAA9F3E-CF06-4097-9E56-7639E306C609.png: actual message bodies and composer visible. Successful retry artifact contains screenshots, not a recorded video; do not claim a recovery video was inspected. Room recovery is proven by original UI test/screenshot, not private-only stage traces.
- No product repair occurred between failure and this pass; diagnostic code unchanged. C63 persistent spinner root cause is still unconfirmed, and one rerun does not prove stability or overall acceptance.
- Confirmed all branch runs completed before proceeding. Requested ONLY large states carried-forward failed job 134539228764. Tool succeeded; attempt 3 now has active job 134555169924, same code/run [44206712654](https://github.com/qianshou330-cyber/pubo-ios/actions/runs/44206712654/attempts/3). No full-failed retry or other code/threshold change. Await result; all unrelated failures remain visible.
- Documentation-only skip-ci checkpoint. C64 remains QA-incomplete, no release/PR/main change.

### C64 isolated states retry — 2026-11-18 02:49 UTC
- Refreshed branch at 2fedd9389b2121a81e5d07de19ef0ac6689d0273 and confirmed all C64 attempt-1 jobs completed, overall failure; no other active test-branch run. Large navigation eventually succeeded; small navigation/video cancelled; remaining final failures are preserved, formal package skipped.
- Authorized single-job retry requested ONLY for small states old job 134476222863, which previously never passed AX initialization. Tool confirmed success. Same C64 code 236cc491176045e72f992e3a64f39a7d6047f013, [run 44206712654 attempt 2](https://github.com/qianshou330-cyber/pubo-ios/actions/runs/44206712654/attempts/2), active new small-states job 134539167538. Preparing fixed build tools at verification; no new test result yet.
- No all-failed rerun, no product code change, no trigger/timeout/gate changes. Large states was not separately retried: its attempt-2 listing is a carried-forward completed failure with original 00:41–01:06 timestamps (new listing ID 134539228764), not a fresh execution. Wait for small-states outcome before deciding further retry.
- This documentation-only skip-ci commit records the action without cancelling it. Inspect actual retry tap, stage captures and recording; keep capture INCOMPLETE distinct from success. C64 remains diagnostic and QA-incomplete.

### C64 recovery evidence — 2026-11-18 01:43 UTC (CI still active)
- [Run 44206712654](https://github.com/qianshou330-cyber/pubo-ios/actions/runs/44206712654), code 236cc491176045e72f992e3a64f39a7d6047f013. Branch refreshed at 8673dad334698b5cd779b7aef95bb461ee3a31de. Large actions/legacy/navigation, small composer/navigation remain active; no code push or rerun during this check.
- Small states job 134476222863 failed before scenarios: XCTest runner timed out waiting for AX loaded notification. Artifact 14385955493 downloaded: chatload-capture-0.json INCOMPLETE, exitCode 0, diagnostic event array empty. This is NOT an executed recovery failure or pass.
- Large states job 134476223058 ran 4 tests / 2 failures. Retry scenario failed at ChatComposerParityUITests.swift:23 inside open(), waiting for chat.input after tapping conversation.user:syntheticpeer. The app-idle notification was not received; subsequent snapshot query timed out. Retry was never tapped. Loading/empty and link-preview retry cases passed; sender-name case failed at initial messages-tab readiness, before preference validation.
- Artifact 14387495934 downloaded; chatload-capture-0.json also INCOMPLETE with zero stage events. Original retry-case recording EB0B56D3-844D-468C-9CF4-67146170B988.mp4 is 208.368 seconds. Inspected final frame about 203 seconds: still on message conversation list, not the private chat/retry screen. This supports an earlier navigation/automation stall; it does not establish the C63 persistent-spinner cause or prove diagnostic logging works.
- Other verified raw counts: large layout 5/5, small actions 5/5. Small layout failed at AX initialization before scenarios. Small video is cancelled (raw log currently BlobNotFound; cause not established). OCR, large video/composer and small legacy failed; do not equate this partial run with acceptance.
- No speculative state repair is justified by these artifacts. Preserve C64 traces; next investigate conversation navigation/idle stall or rerun the isolated failed states job only after all current jobs finish and concurrency is rechecked. Do not increase timeouts, bypass real taps, hide spinner, or claim empty diagnostic output means success. Docs-only skip-ci checkpoint preserves active work.

### C64 follow-up — 2026-11-18 00:39 UTC (partial, running)
- Code SHA 236cc491176045e72f992e3a64f39a7d6047f013; [run 44206712654](https://github.com/qianshou330-cyber/pubo-ios/actions/runs/44206712654) is still running. Checks, candidate-package and H5 reference succeeded; small states, large layout/composer and both video shards are running; remaining shards/OCR queued at this snapshot.
- Raw checks log confirms Swift 178/178, Python 143/143 and Node receipt 2/2. Candidate raw log confirms two BUILD SUCCEEDED entries (simulator/device packaging). Artifact 14383994072 exists and remains QA-INCOMPLETE; not downloaded or installation-verified, not an accepted release.
- No states artifact has uploaded yet. Recovery-stage logging and retry outcome are therefore still UNVERIFIED; a successful package is not evidence that recovery works. No code changes, retries, cancellations or new diagnostic runs started in this check.
- This follow-up touches documentation only with skip ci, preserving active C64. Wait for states evidence before choosing a product fix; retain all gates.

# Current checkpoint: 2026-11-18 00:18 UTC
C63 run 44182546174 has ended failure; all jobs completed. Large actions failed but raw log fetch returned BlobNotFound, exact cause unverified. C64 is observation-only recovery diagnostics, not a repair: inspect synthetic private load stages and transport stages in existing states artifacts. Preserve all gates; no accepted release. Local Python 143/143 and Node 2/2 pass; Swift/Xcode unavailable locally. See latest FIX_LOG entry. The earlier snapshots below are historical.

# PUBO agent handoff

Snapshot: 2026-11-17 16:51 UTC. Refresh branch and Actions before acting; this is not a live status page.

## Latest code candidate: C62 (2026-11-17 19:15 UTC)
Private-chat metadata no longer carries the 44pt overflow menu; a visible sibling target matches the existing group-chat pattern. Menu actions, account guards and touch minimum stay unchanged. Local Python 139/139 and Node 2/2 pass. New both-theme frame checks and actual C62 screenshots remain pending CI, not acceptance. This does not fix OCR or the other C61 failures. Preserve all original gates. See FIX_LOG.md before continuing; do not import the separate unpushed OCR probe or start overlapping CI.

## Repair records
Every fix or diagnostic change must follow [AGENTS.md](../AGENTS.md) and append to [FIX_LOG.md](FIX_LOG.md), including failed attempts, verification gaps and follow-up results.

## Latest checkpoint (2026-11-17 18:00 UTC)
Candidate retry job 134235071422 succeeded at 17:47:33 UTC. [Artifact 14352744864](https://github.com/qianshou330-cyber/pubo-ios/actions/runs/44117699042/artifacts/14352744864) is present and downloaded/verified. IPA SHA256: `6f9ec9d7761bd291d5b31d3498dab8737c14f2e85dbe14eb084bce9c5492edf9`, 5581258 bytes. It is iPhoneOS arm64 unsigned build148, QA-INCOMPLETE, not full acceptance or verified installation. No active/queued runs were found. Do not rerun the recovered package upload.
OCR raw reports confirm correct strings but confidence 78.208992 / 55.412251 / 74.187180 below unchanged 80. Do not lower the gate or relabel controls. See FIX_LOG.md for evidence and remaining failures.

## Historical checkpoint (2026-11-17 17:35 UTC)
This section supersedes the earlier 16:51 status below; older details remain historical.
- Original C61 completed failure. Confirmed no active/queued test-branch jobs before rerunning only candidate-package (old job 134162066990; active retry job 134235071422, same run 44117699042 and code SHA 55351e1). Upload result is pending; no new delivered IPA.
- Verified original passes: both chat layout groups 5/5, both chat action groups 5/5, small states 4/4, large legacy 5/5, small video 4/4, checks and H5 reference.
- Failures: small legacy/navigation, large video/states at Accessibility initialization; small composer at simulator-service recovery timeout; large composer snapshot timeout plus 1800s budget; large navigation exceeded its separate 2700s budget near final case; OCR same 3 positive controls; candidate artifact service failed after 5 upload attempts. Formal package skipped.
- Do not repeat the candidate retry while it is active, push a cancelling code commit, or reinterpret a QA-incomplete candidate as acceptance. Follow the dated detail in FIX_LOG.md.
- Only this documentation checkpoint uses skip ci. C61's genuine failed checks remain failed and visible.

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

## 2026-11-17 18:03 UTC / C61 screenshot evidence inventory
Status: evidence inventory only; QA INCOMPLETE, not visual acceptance.
Code: `55351e1922a1141ddc3eecd7e720f853bc4b232f`; [run 44117699042](https://github.com/qianshou330-cyber/pubo-ios/actions/runs/44117699042).
- Verified 8 baseline pairs (private/room × small/large × light/dark), 16 original PNG files. Private captures are in layout artifacts 14352065341 / 14351519255; room captures in actions artifacts 14349472670 / 14349480581; H5 reference artifact 14343668173.
- All 16 PNG files decode and have SHA-256 manifests in the prepared evidence archive. Small pairs are 750×1334 on both sides. Large iOS originals are 1320×2868, H5 880×1912 (different raster scale); do not compare unnormalized raw pixels.
- H5 is an actual public bundle snapshot with synthetic ChatParity fixtures and blocked production APIs, not a live production-account recording. iOS captures are Simulator screenshots, not physical-device verification.
- Inspected private-small-light pair visibly differs in header, spacing and reaction rendering. Pair availability and passing scenario assertions do not establish 1:1 parity. Full visual review and outstanding failed suites remain open.
- Changes: documentation only (`docs/FIX_LOG.md`, `docs/AGENT_HANDOFF.md`); no code, gate, retry or timeout changes and no new CI run.

## OCR follow-up (2026-11-17 18:45 UTC)
Full 189-sample read-only replay on the original Linux 5.5.0/Leptonica 1.84.1 stack exactly reproduces all saved decisions; the same pinned model and verified PNG inputs differ on CI macOS 5.5.3/Leptonica 1.87.0. This isolates environment-associated drift, NOT its exact version/platform/SIMD cause. No production gate changed and no current 5.5.3 pass is claimed. Three valid positives also improve on CI and one known clipped false accept disappears. Next: controlled same-platform engine/library comparison before a gate-preserving fix. See FIX_LOG.md for full results; do not rerun the recovered package upload or blind full UI.

## C62 checkpoint (2026-11-17 20:35 UTC)
Large private-chat both-theme scenario passed, including new geometry and menu round-trips; its layout job still failed 2/5 other methods. Menu 44x44pt / metadata 13.33pt confirmed by attachments, and actual light screenshot inspected. AX bubble frame is text bounds, not full padded bubble. Small-screen and remaining jobs still pending; no full acceptance. One failed tab-readiness sample completed at 8.127s despite valid geometry/hittability, directly showing AX queries exhausting the unchanged 8s budget. Do not weaken it. See FIX_LOG.md and run 44156868718; avoid overlapping pushes.

## C62 checkpoint (2026-11-17 21:00 UTC)
Small layout/actions now each pass 5/5; both-size private target scenario passes, not whole acceptance. C62 likely shadows existing chat.text.* with new ancestor chat.bubble.*; large recovery waits for chat.text.private0001 and fails. Local C63 removes ancestor identifier and measures original text identifier with unchanged strict geometry/menus; 140 Python + 2 Node pass, no Swift/CI yet. Do not push until remaining large navigation/composer finish. See FIX_LOG.md; no package is fully accepted.

## Latest candidate C63 (2026-11-17 21:42 UTC)
C62 has ended failure; no active/queued work before C63. C62 large navigation passed 13/13, formal package skipped. C63 removes the new ancestor chat.bubble identifier to preserve original chat.text accessibility, and measures that existing text element with identical geometry/menu gates. Local Python140/140, Node2/2 pass; Swift/runtime restoration not yet verified. Await C63 CI before claiming repair or using screenshots. Do not weaken existing recovery/geometry/time budgets; OCR and other failures remain open.

## C63 checkpoint (2026-11-17 22:39 UTC)
Large layout passed5/5; both-theme private scenario successfully queries original chat.text IDs, real menu round-trips and unchanged geometry. Four attachments confirm44pt menus and13.33pt metadata, same C62 geometry. Small layout and independent recovery states still pending; do not generalize to full recovery/acceptance. Candidate artifact14374964353 exists but IPA not downloaded/verified in this check. Active jobs remain; do not push code/retry concurrently. Full details in FIX_LOG.md.

## C63 checkpoint (2026-11-17 23:38 UTC)
Small layout/actions5/5 confirmed; both-size text-ID/layout target passes. Independent recovery still fails: small retry video remains on loading at~192s, not merely missing AX identifier; large states never initializes. Do not claim full retry repair or call all failures environmental. Next bounded diagnosis must distinguish request/state synchronization/cancellation/epoch/loading phases without relaxing completion. Large actions remains active; no overlapping push. See FIX_LOG.md for raw evidence distinctions.
