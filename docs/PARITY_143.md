# Build 143 candidate: Drive and channels

This candidate builds on 142. It is not proof that every page matches H5.

## Added and changed
- Drive: sensitive file preview/selection requires an explicit per-use confirmation, preserves the sensitive flag and reads current metadata before disclosure. Picker rejects stale MIME/ID changes, prevents repeated taps and cancels requests on exit/account change.
- Avatar/background selection: only a confirmed-sensitive picker callback can authorize using such an image; ordinary upload paths retain their existing safeguards.
- Channels: name-only/name-and-description search modes, empty-query guidance, stale-response isolation, and account-policy checks both at Create entry and before submission.
- Synthetic core and UI tests added. No production account mutations are part of these tests.

## Reference and verification boundaries
- Source-based comparison: verified 2026-10-31 H5 snapshot, with exact files documented in DRIVE_PARITY_143.md and CHANNEL_PARITY_143.md.
- Current public H5 timeline screenshots use real published bundles with synthetic API/media and record their provenance. They do not establish private Drive/channel visual identity.
- Drive/channel screenshots for this candidate must come from its exact iOS CI commit. Until matched H5 private-page screenshots exist, label them native evidence only.
- Linux preflight: Python packaging checks and diff checks. Swift compilation, device packaging and UI regression require Mac CI and must be reported separately.
- No signed installation, physical-device, upgrade, iOS17 runtime or full-site acceptance claim. No main merge, PR, release or production deployment.

## Build142 follow-up fixes
- A real follow alert exposed parent/child accessibility nodes with the same ID: target the first button inside the first alert, retaining both keep and confirm assertions.
- Privacy UI test now taps the switch control and verifies its actual value before dependent-state assertions; final Mac rerun is required.
- Profile editor adds a keyboard-dismiss action, and tests scroll only within the visible form (the142 recording showed the keyboard covering the birthday field).
- Post-length recovery re-queries the rebuilt text accessibility node, still requires exactly60 characters and an enabled send button, and saves diagnostics on failure.
- Isolated-backend warmup failures now record an explicit phase and a bounded synthetic screenshot, without logging credentials.

Build142 evidence: 124 core and6 package tests passed; small UI10/14 with four failures. Large UI and second isolated-backend attempt still running when143 was prepared. First backend attempt timed out during simctl launch before XCTest. No full acceptance claim.
