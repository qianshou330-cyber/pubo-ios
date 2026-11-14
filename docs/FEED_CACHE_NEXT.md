# Feed cache + actual first-frame candidate (not validated on iOS)

Base: 79e93b5, independent local branch; original worktree untouched.

## Changes
- Timeline snapshots (public notes only, first 100) enqueue value-type Sendable snapshots; encoding and protected atomic write execute on a utility serial queue.
- All existing ProtectedStore read/save/clear operations share that ordering domain. Clear drains earlier writes and removes afterward; snapshots cannot resurrect cleared data after clear returns. Pending snapshots coalesce by account+key. Account switching/logout invalidate pending work before changing generation; already executing writes finish before later clear. Existing synchronous settings save semantics are retained.
- No animation settings, animation decoder, durations, video playback or external media rules removed.
- Opted-in DEBUG fixture can decode one bundled H264 red video through the production AVAssetImageGenerator path. All other synthetic video URLs fail closed. Missing/broken thumbnails, valid thumbnail and unknown video cases have UI tests. Fallback tests assert red pixels (not just element existence) and retain screenshots.
- Queue unit tests cover off-main execution, deletion ordering, cancellation, coalescing and account-key isolation.

## Validation performed
- git diff --check passes.
- ffprobe: bundled generated fixture H264, 160x90. Generated entirely from ffmpeg red color source, no external assets.
- Swift and xcrun are absent in this Linux environment. No Swift compilation or Swift/iOS test success claimed. four-tabs-tests.py reaches xcrun then fails FileNotFoundError. check-contracts.py requires schema/source inputs and was not run successfully.

## Required gates before delivery
- swift test (including OrderedSnapshotQueueTests).
- iOS build then PublicVideoPosterUITests on both sizes; inspect retained red poster screenshots.
- Existing animations, account switch/logout, protected store and timeline regression suites unchanged and must still pass.
- Live scroll traces and device playback/cancellation/account-switch tests still required; no FPS score assigned.

## Risks / scope
- sync reads/settings writes/logout can wait for a currently executing bounded snapshot; only hot-path pagination disk write was moved. No claim of fully asynchronous disk access.
- Cache write errors remain nonfatal as before. Memory-pressure/disk-full behavior needs device testing.
- No next-N first-frame prefetch, animated byte cache or new scrolling policy is introduced by this minimal candidate.
- CI must explicitly select new PublicVideoPosterUITests if its test selection is allowlisted; no existing gate is loosened.
