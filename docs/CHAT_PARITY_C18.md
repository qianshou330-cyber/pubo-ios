# C18 follow-up from actual C17 screenshots

Prepared against C17 `06ccb5ac9543de615ffb02fc7dbc9fdd38f62a98`; not a declaration of runtime success.

C17 small native's original 9 methods passed. Its real screenshots and four same-data/media H5 pairs established detail-tab removal and visible composer tools, but also exposed remaining layout/accessibility problems. The separate 8-method presentation suite has its own outcomes, not inferred from the original nine.

## Targeted changes

- Chat TextKit receives an already-scaled SwiftUI subheadline point size. Ordinary note rendering retains its prior UIFontMetrics path. The existing large-text method asserts the unique actual TextKit text child of the fixed-message bubble exceeds 22pt in height. C17's ordinary-size AX tree measured that text at 15.5pt (its wrapper was 15.7pt); the large-text problem was screenshot inspection, not a large-text AX measurement. This extends the existing composer-reachability test rather than inferring text scaling from a reachable send button. Accessible message label/value contents are preserved; no diagnostic replaces the message text.
- Center chat section tabs when all fit; retain horizontal scrolling at larger text sizes. Do not shrink labels or remove the 44pt targets.
- Omit empty link-card containers so they do not introduce extra inter-row spacing. Put the own-message menu after its time/status, matching the inspected H5 ordering. Metadata controls still keep 44pt hit regions; the residual spacing difference is not claimed fixed.
- Pin the H5 job to Ubuntu 24.04, rather than the incompatible moving Ubuntu-latest image.
- Serve exact native media bytes to H5. Missing media is an error; native source and media hashes are recorded. The earlier 1×1 substitution is retained as invalid same-media evidence, not silently counted as parity.

- Replace only the chat avatar fixture with a dedicated opaque 128×128 geometric profile icon shared byte-for-byte with H5. The former 320×180 transparent media probe made tiny dots under DEBUG fit and cropped fragments under H5 cover; this is not evidence of broken production avatars. DEBUG avatars now use fill like the unchanged production AsyncImage path. Existing still/GIF animation fixtures are byte-for-byte preserved.

- Correct the new recovery test's group locator to the established `room.bubble.room0001`, retaining the wait and actual message-content assertion. C17's failure AX tree and captured video showed all three messages had recovered; the ancestor accessibility identifier replaced the inner UIKit identifier. C17 remains 7/8, not retrospectively reclassified as pass.

- Adapt the three old navigation scenarios that tried to tap tabs inside a conversation or demanded tabs during a chat push. The approved UI now hides them: use real Back and require the messages root/tab selection, then exercise independent friend stacks, account clearing/draft isolation and other push destinations as before. This intentionally no longer claims that a chat-detail stack survives a direct tab switch: real Back pops that detail under the approved interaction. All 13 methods, strict zero-failure gate, screenshot/pixel/OCR requirements remain. C17 navigation-large 9/13 is retained as a failure, not re-labelled. The scanner failure's original video shows the menu open at49s, then the generic helper swiped it away at51–55s after an immediate non-hittable poll. Menu entries now use the actual Button and an explicit bounded hittable wait, never list scrolling. The real tap, fallback text and no-camera-alert assertions remain; no skip or coordinate bypass.

## Evidence and limits

The released-to-user C17 artifact remains a QA-INCOMPLETE unsigned candidate. It is not re-labelled as C18. Preserve C17's raw failure records and ongoing jobs; do not push this same branch until its run completes. New source-contract tests are static guardrails, not UIKit runtime evidence. Swift compile, scaled wrapping, large-device keyboard, centered/overflow tabs and subsequent original screenshots must be checked on the new commit.

Still unresolved: exact native navigation styling, compact metadata with accessible hit regions, H5 date separators, emoji rendering, complete MFM behavior, full media corpus, live account/APNs, physical/minimum-iOS 17, performance traces. No production writes, main changes, PR or Release.
