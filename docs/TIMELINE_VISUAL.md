# Dynamic timeline visual calibration — 0.9.3 candidate

Baseline: 0.9.2/build128. Scope: signed-in timelines and guest public feed only. Explicit `NoteAppearance.timeline` is independent of subscription ownership. Other consumers default to `.standard`; the four bottom destinations and existing interactions are retained.

2026-11-05 live H5 assets were measured in the in-app browser at a 440×956 CSS viewport with synthetic timeline data. Body/name/account: 12.6px; body line-height 17.01px; time 11.34px; avatar 46px with 10px content gap; post padding 14×16px. Actions use 16.3px outline icons, 28px gaps; reactions have 42px visual height, 6px horizontal padding and 13.23px counts. Native actions retain discrete 44pt hit boxes and dynamic type, so this is not a pixel-identical web rendering.

Selected Tabler 3.35.0 vectors and MIT license are bundled without a runtime framework. Reactions, quote previews and text receive the explicit appearance value. Original streaming, GIF, reference, pagination and motion behavior is unchanged.

Current status: implementation and local packaging-unit checks complete; Mac builds, actual UI evidence, isolated mutation receipts and release verification pending. No new IPA is accepted yet. Main is unchanged; build128 backup branch is `backup-main-20261105-before-timeline-093`.

Physical iPhone, minimum iOS17 and signed installation/upgrade remain unverified. Evidence is generated using simulator UI and the in-app browser; production writes are prohibited in validation.
