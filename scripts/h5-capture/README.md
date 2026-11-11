# PUBO isolated H5 reference capture

Status: cloud end-to-end Chromium capture passed for both 375×667 and 430×932 CSS-pixel light screens on 2026-11-11. Initial light cases loaded 62 real JavaScript bundles, fetched the synthetic timeline, rendered the expected post, and reported zero runtime errors, failed HTTP responses, console errors, or blocked requests. Build142 extension also passed all four size × system-theme cases, producing eight actual H5 screenshots (normal and filters) on 2026-11-11 14:32–14:33 UTC. CI integration still requires its own run; this success is not a native/H5 pixel-parity assertion.

Uses the actual HTML and bundled static frontend published at https://bolubo.com/ with the repository's TimelineParity.json synthetic account/posts/API. It does not redraw H5. Assets and HTML are hashed in report.json. A newly fetched production bundle can change and require fixture endpoint updates; unknown endpoints deliberately fail rather than returning misleading success.

## Run

From h5-capture:

```sh
npm ci
npx playwright install chromium
FIXTURE_PATH=../../App/Resources/TimelineParity.json npm run capture
```

On Linux, use `npx playwright install --with-deps chromium`. A pinned Python 3 and Node 22 CI job is recommended. `H5_HTML` may reference a previously downloaded actual HTML snapshot. By default public-home.html is downloaded once and reused; remove it only when intentionally updating the reference version. Static cache is keyed by asset path. Do not cache these files across deliberate reference-version changes without reviewing provenance.

The script starts its own loopback server, waits for readiness, captures 375×667 and 430×932 CSS-pixel screens at scale 2 in both light and dark system themes, plus the actual expanded filter menu, and closes browser/server on success or error. It uses real current wall-clock time; report timestamps document capture conditions. It defers the optional initial-account setup via the visible “一会再说” button and confirms the visible “OK” dialog; this action is recorded. It retains the timeline tip card. It never removes dialog DOM or injects replacement UI/CSS. Local storage contains a synthetic account only, and production account credentials must never be supplied.

## Validity gate

A passing case requires actual JS bundle responses, a successful fixture timeline request, visible first-post text from TimelineParity.json, interactive page controls, no uncaught JS errors, and no failed HTTP responses. It verifies the H5-owned `html[data-color-scheme]` matches the requested system theme, then clicks the real header options control and asserts the filter labels. It writes `h5-{small,large}-{light,dark}.png` and matching `-filters.png` files. If any gate fails, exit code is 1 and only a clearly named `DIAGNOSTIC-NOT-PARITY-*` image may be emitted. Never present a diagnostic as an H5 comparison. Inspect consoleErrors and blocked requests in report even when the gate passes; third-party fonts/icons may be intentionally blocked and affect appearance.

## Safety

Browser routing permits only its exact loopback origin; service workers are blocked and CSP restricts connects/media/forms. Server forwards only GETs for explicit public static path prefixes and never forwards API requests, cookies, authorization, submitted data, or any POST. Redirects are rejected. Unknown API calls return 501. A fresh browser context is used for each size. The server binds only 127.0.0.1. Do not expose this fixture proxy publicly.

## Known comparison limits

- Existing iOS screenshots were generated with the native test fixture, not at this capture's time. Relative dates and OS/browser chrome differ.
- Media is currently a synthetic one-pixel image placeholder, not the native fixture's full GIF/image assets. **Media parity is not claimed**; do not compare media dimensions/colors until exact fixture bytes are ported.
- H5 source is fetched from the live public deployment, not asserted equivalent to the Oct31 source archive. Provenance hashes must accompany any result.
- Music chart and account/preference APIs are synthetic minimal fixtures. Additional API contracts may need completion when run on CI.
- Dark and expanded default-filter menus are covered. Filter toggle semantics and unrelated app pages are not covered by this screenshot harness.
- Browser/platform typography can differ. These references are for layout review, not a justified zero-pixel-diff assertion against native screenshots.

The repository social-alignment.yml includes the independent visual-reference job. Upload artifacts on failures so fixture gaps are diagnosable. Do not mark visual parity complete solely because IPA packaging passes.
