# C77 local host diagnostic draft (not an optimization)

Base: `6ba9ef65b669fa8728b50cf5e2a44e328033bb3f`. Overlay only this directory and
`scripts/test_timeline_capture_bench.py` into the full pinned repository.
The local draft's App/Core/Package copies are reference inputs, NOT changes.

Run manually on an authorized Swift/macOS host:

    python3 scripts/timeline-capture-bench/run.py

No CI/workflow or remote action is added. The wrapper checks exact Git blob
fingerprints for the App expression, genuine public Core implementation, Record /
JSONValue and root package manifest. Any drift aborts pending review; do not
silently repin. It builds the actual repository PUBOCore as a local package
product in release, without copying/reimplementing capturedIDs or changing the
root package. Each attempt writes under a new build/timeline-capture-bench/attempt-* directory, never in source.
The validation reconciles warmup and measured slots, raw batch durations, and reported median/p95 before writing report.json.
Swift is unavailable on the draft host: no native compile or timing results exist.

## What this measures

- Active=true `notes.filter { visibleIDs.contains($0.id) }`, followed by genuine
  `TimelinePresentation.capturedIDs`, at 20/200/2000 loaded wrapper records.
- Exactly eight visible records in each of two precomputed alternating sets.
  Each wrapper has a reply chain extending beyond depth4 and one renote. Exact
  expected identity sets are checked before timing (depth0..3 + renote only).
- Five warmup rounds, forty recorded rounds, 100 operations/batch. All nine
  size/arm combinations are reproducibly shuffled each round with logged order.
- Arms: full filter+traversal, already-selected eight traversal (not an app fix),
  and no-op returning the same expected Set. Each includes the same noinline
  observable consumption. No-op is overhead context, NEVER subtracted.
- Raw monotonic nanoseconds, batch ns/op, median and nearest-rank p95 of batch
  means. This p95 is NOT an individual visibility-event p95. Review raw samples
  by round/order for drift; no arbitrary pass threshold or hidden outlier removal.

Not measured: stream.captureNotes side effects, SwiftUI diff/layout, view
lifecycle rate, gesture delivery, GPU, network, decoder, memory pressure, device
thermals or actual iPhone/Simulator frame hitches. Fixed eight-record nesting is
one workload, not all production content. Host compiler/optimization, scheduling,
allocation and cache effects remain. Release Swift collection work may differ
from Debug simulator UI. This cannot establish that captureVisible causes C76
scroll pauses; it can only quantify the isolated mechanism on its recorded host.

## Read-only future second-page video sketch (NOT IMPLEMENTED)

Do not combine with C76 controls before their native results and root review.
Use an opt-in synthetic-only fixture variant with a dedicated video ID located
strictly beyond the first *filtered* 20 records. Verify exact pagination and
untilId, not just a position in the raw array; current filters and row prefetch
can otherwise expose/decode it early. Keep existing first-page four video tests.
Use the real bundled red MP4 and existing decoder path; no painted red placeholder.
A dedicated real media target would be media.open.<unique-second-page-id>.
The cache key includes the actual video and thumbnail URL strings within
the session generation, not just row/file ID. For an isolated synthetic trial,
a distinct query marker on the existing fixture URL can make a new key; the
fixture resolver checks host and path, so it still selects the bundled MP4.
Verify the older-page response and cache miss / decoder-start events separately.

Distinguish cache-cold (no cached poster at the actual start of work) from
viewport-cold (no decode started before the row was visibly on screen). An
already-visible first frame at the first unobscured observation is useful
prefetch evidence, not a measured zero-millisecond viewport-cold decode.
App row onAppear is lazy-layout/prefetch evidence, NOT viewport visibility. A future passive DEBUG
synthetic receipt would need the actual unobscured viewport intersection, stable
post/media ID, PID and monotonic time, plus real decode/render facts. Never move
the view or change player state to satisfy the test.

First-visible -> rendered-red timing must share ONE monotonic clock domain.
UI screenshot sampling could timestamp bracketed captures with test-process
uptime and compute an interval/bound; its AX/screenshot latency must be included
or separately disclosed. Do not subtract app uptime from video frame PTS or
wall-clock log dates. Pixel validation must use the actual current media crop,
retain baseline red fraction >0.35, and distinguish loading/unavailable from
black pixels. Capture intermediate frames and occlusion, not just final ready
state. Report sample interval and onset uncertainty; absent onset, prefetched
frame, missing crop or clock correlation => INCOMPLETE/UNAVAILABLE, never 0ms.
Functional pass remains separate from latency observation; no new latency pass
threshold without a reviewed baseline. Real-iPhone smoothness stays unverified.
