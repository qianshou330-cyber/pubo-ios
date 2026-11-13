# Chat date and time alignment (next candidate, not runtime-verified)

Scope: chat date separators and relative labels only. No API, URL, timestamp,
message order, pagination, row ID, metadata hit area, or global formatter changes.

## Evidence and provenance

Inspected local H5 snapshot (commit and live-deployment equivalence UNCONFIRMED;
see `chat-h5-source-manifest.json`) and the actual C18 large-screen PNGs in
`PUBO-C18-large-chat-comparison`. C18 public-build screenshots corroborate the
visible normal-date ordering/shapes and first-message 2-week label; they do not
prove every snapshot branch matches the deployed build.

Snapshot SHA256:
- `pages/chat/private.vue`: `3b2b327a92348ff858ac286ca5ac789c3633a0ecaa3f4d4b12f03259ee2eb088`
- `pages/chat/room.vue`: `4be577fb45121b84d0380210112ca37fe03296d9ea8b953610e78fb81320b7cf`
- `utility/timeline-date-separate.ts`: `ba0d5187c2243651df3d1f8922fa8fae44f83fc6cb9a10483f72bccf379c2f25`
- `components/global/MkTime.vue`: `18d4c00030100b0abd9133bd63123626b6ec3b2ab4c3bd5dcee680be8cb6faa4`

## Date boundary

Input stays chronological. The structured pair exposes older/newer dates.
Private: centered newer · older text, no horizontal rules. Room: older | newer
inside a thin capsule with up/down chevrons. Accessibility remains one static
text element with a spoken date label; decorative symbols are ignored.
Dates use the existing local calendar/timezone. Across years, both dates retain
native year numbers: an explicit enhancement over H5's month/day-only rendering.
Dynamic Type scales the 85%-of-14-point label and proportional capsule padding.
Exact font rasterization, chevron glyphs, and spacing require simulator review.

## Relative time

Only ChatRelativeTime uses the new zh-CN policy. Year/month/week/day/hour thresholds
are fixed seconds (365/30/7/1 days and 1 hour), rounded nearest with positive halves
up. Minutes and seconds truncate. Past boundaries use >=; future boundaries use >,
matching MkTime. Thus exactly 60 seconds in the future reads 0秒后 in that snapshot;
this oddity is retained explicitly and tested. From -3 through <10 seconds ago is
刚刚. Nil/nonfinite dates produce 没有, matching the snapshot's Chinese invalid label;
existing call sites still omit labels for unparseable source timestamps.

The existing 60-second SwiftUI refresh remains; H5's shared clock updates every
10 seconds. Between updates labels can differ at boundaries. No app-wide clock
or formatter behavior changes. Unit tests fix now and calendar/timezone; there is
no synthetic replacement of production timestamps or screenshot clock.

## Verification

Added core tests cover 7-day and 10.5-day boundaries, truncation, future/invalid
policy, timezone-local boundaries, and cross-year display. The existing private
ChatAlignment test now expects newer · older; test method count remains nine.
Linux workspace has no Swift/Xcode, so these Swift tests and SwiftUI rendering
must run in the next authorized macOS CI before claiming a pass.
