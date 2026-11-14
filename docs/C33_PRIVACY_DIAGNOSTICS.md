# C33: privacy switch event evidence (not a confirmed fix)

Base: C32 f713b7ee7e930e1a3ba9761a45edbf879ccce29a.

C32 large legacy tests finished 4/5; the dark autoAcceptFollowed transition
timed out. Large chat was 10/10, small composer 4/4. Large navigation completed
10 methods before its existing 2700-second budget expired; it is not a pass.

This candidate adds observation only in DEBUG with --ui-testing. The original
SwiftUI Toggle, native control, binding setter, accessibility, test tap, and
8-second equality gate are unchanged. A non-interactive background probe adds
its own UIControl targets without replacing any existing target or recognizer.
It logs fixed setting keys, native enabled/value/geometry, center hit ownership,
touchDown/up/cancel when emitted, and valueChanged alongside the existing setter
log. No account identifiers, messages, credentials or production preferences
are recorded. Release builds omit the probe entirely.

Interpretation: UISwitch may implement its gesture without sending every
UIControl touch event. Absence of touchDown alone does NOT prove that no touch
arrived. Compare valueChanged, setter, layout, XCT synthesized event and video.
Ambiguous or missing native controls are logged rather than guessing a row.
No event is injected and no state is forced. A successful run alone does not
prove that intermittent failures have been fixed.

Local Linux checks: Python 98/98; Node 2/2; git diff --check passed. Swift/UIKit
compile, native UI tests and screenshots require macOS CI. No new runtime pass
or product fix is claimed before that evidence is collected.
