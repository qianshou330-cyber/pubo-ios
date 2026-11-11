# Build 142 candidate: profile and account settings

Reference remains the verified 2026-10-31 H5 source snapshot documented in PARITY_141.md. Private live profile/settings were not authenticated and are not claimed visually matched.

## Changes
- Profile display: location, birthday, registration date, post count, and exact-value server verifiedLinks badges (link validation, not identity verification).
- Profile editing: location and birthday, nullable empty values, nickname30/description500 counters and validation, max16 additional fields and omit empty name/value pairs. Gregorian YYYY-MM-DD validation, including leap years; no unsupported future-date rule.
- Privacy: autoAcceptFollowed enabled only for a locked account; disabling parent preserves saved child value.
- Account security: email controls require explicit enableEmail capability and recheck before mutation. Password/TOTP controls remain independent.
- Actual H5 reference capture now includes two viewport sizes, light/dark, normal/filter-menu (8 images), live UI interactions and theme verification. Synthetic media remains placeholder. Capture logs record real onboarding dialog deferral.

## Tests
New core tests cover account dependencies and profile formatting/validation. New UI classes cover both-theme profile validation and privacy dependent switches plus missing-email controls. Tests only edit synthetic local drafts; never submit production profiles/emails.
Cloud H5 capture succeeded for 4 size/theme cases on 2026-11-11 at14:32:41–14:33:03 UTC, with zero runtime/console/HTTP/blocked errors. Mac compilation/UI results must be recorded for the eventual exact commit before reporting success.

## Remaining
All pages are not yet fully matched. Timeline and chat visual deltas, channels/contacts/Drive sensitive media, notifications/discovery/admin full audit and real-device testing remain. No production deployment/main merge/release or signing included.

## Recovery and regression closure (pending CI)
- Build141 CI finished with small 10/11, large 9/11 UI tests. Follow confirmation omitted the cancel/keep action in the platform confirmationDialog; pagination auto-load could retry after a queued first failure. These are not dismissed as only test errors.
- Build141 isolated backend joint workflow succeeded; it does not replace this batch's final-commit validation.
- H5 CI dependency installation failed at package DNS. Use the official version-matched Playwright image for the browser/OS dependencies instead of an apt install at runtime. Capture remains real H5, synthetic data only.
- Before pushing142: six Python packaging tests pass; Python scripts compile and capture.mjs parses. Swift/UI verification remains macOS-only.
