# Private-chat horizontal inset candidate (not runtime-verified)

C19 SE3 ordinary private chat shows avatar paint at approximately x17pt; the
keyboard screenshot shows x1pt and a simultaneous upward shift. Room shows x17pt
in both states but approximately 33pt from tabs bottom to first avatar paint.
These are screenshot observations, not proof of a unique scrollPosition cause.
Avatar paint is inset one point inside its 44pt navigation button.

This candidate changes only private chat's inset ownership: inner LazyVStack
keeps vertical padding16, while ScrollView owns horizontal contentMargins16.
It does not shrink the viewport, change scrolling IDs/anchors/nearBottom, or alter
room top insets. The goal remains a real 16pt horizontal button inset, not a new
coordinate definition that makes a test pass. Private avatars receive stable IDs.

The existing four composer tests (two helper scenarios × private/room) retain all
tool, keyboard, navigation and draft assertions. Added geometry checks run at
ordinary, keyboard and restored-draft stages, in both themes and matrix sizes.
They use the actual ScrollView AX frame and first select avatars solely by full
vertical containment between viewport top and viewport/composer bottom. At least
one such candidate is required. Every candidate must then be 44pt minimum in both
dimensions, fully horizontally contained and inset16±1pt. Horizontal clipping or
incorrect width must fail validation, never exclude an avatar before testing it. No swipe/tap is added to satisfy geometry, and no visible
avatar is a failure rather than a skip. Attachments retain each tab button frame,
viewport, composer, every avatar frame and the full AX hierarchy.

Existing ChatAlignment room-top16pt assertions are untouched. Long content may
legitimately scroll vertically; the new assertions do not force first-row top
position. The room-top33pt issue remains open pending actual viewport/inset data.

The next four-tabs checks job also runs the existing optional macOS Darwin gate
preflight and preserves its log even if it fails. A host-process pass is not
proof of Simulator sandbox behavior. No workflow was triggered for this patch.

Validation in Linux: source contracts and existing Python/Node tests only.
Swift compilation, true keyboard/AX geometry and regression results require Mac
CI; do not describe this candidate as a verified layout fix before that run.
