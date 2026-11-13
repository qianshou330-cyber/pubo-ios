# World feed media pass (2026-11-13)

## Source observations (not a measured frame-rate diagnosis)
- `TimelineView` already uses stable note IDs and `LazyVStack`; existing timeline/reaction/GIF animations are preserved.
- `PublicAnimatedAsset` cleared decoded images on disappearance and fetched/decoded again on return, with no public in-memory preview cache.
- Static ImageIO thumbnails could defer decompression until display; decoding now requests immediate caching inside its detached task.
- Native videos without `thumbnailUrl` displayed an empty color rectangle. H5 `MkMediaVideo.vue` uses the server thumbnail when present and a metadata-preloaded video otherwise.

## Changes
- Public still-image memory cache: 24 MiB cost target, 80 entries, generation-separated keys and purge on account-generation change; no disk cache, no protected chat attachments, no GIF flattening.
- Server video thumbnail preferred; if missing/failing, asynchronously request transformed video frame at t=0. Maximum output 720x720, at most two extraction jobs, cancellation-aware queue, eight-second cancel deadline, cancel on view disappearance or scene inactive. No player per feed row.
- Video area keeps stable aspect ratio, shows loading/error rather than an unexplained blank/black tile. Sensitive media stays behind existing reveal gate.
- Offscreen video image references released; cache can cheaply serve rows returning onscreen.

## Limits
- NSCache costLimit is advisory, not a process-memory ceiling. Visible images, framework buffers and GIFs consume additional memory.
- AVAssetImageGenerator may read substantial remote video bytes (e.g. MP4 metadata at end). A 720px limit constrains output, not network volume. Production server-generated posters are the preferred reliable path.
- An actual black frame in the source at t=0 can remain black. No fabricated scene or guarantee that every remote asset has a decodable first frame.
- Existing Python checks: 54 passed on Linux. This is not a Swift compile, UI test, or performance measurement.
- macOS build, same-device Release before/after scroll trace, mixed long-feed screenshot/recording, first-frame error/timeout/reappearance tests and physical iPhone scrolling/thermal testing remain NOT_RUN. Do not call this validated silky scrolling or a completed IPA.

## Verification before acceptance
1. Build current independent commit with pinned Xcode, run existing timeline GIF/UI regressions.
2. Use same 200-post mixed image/GIF/video fixture and device; record ten down/up sweeps, image refetch count, p95 frame time/hitches, peak/resident memory and network bytes before/after. Retain animations and same data.
3. Verify server-poster path; absent/broken poster fallback; offline/slow/cancel; backscroll; background; account switch; hidden sensitive video no early request. Confirm <=2 fallback decoders.
4. Capture real H5/native same-data light/dark and small/large screenshots. No UI screenshots captured in this Linux pass.
5. Physical iPhone Release acceptance required; simulator UI success alone is insufficient for smoothness.
