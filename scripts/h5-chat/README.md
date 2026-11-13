# Actual H5 chat reference capture

Uses the actual public `https://bolubo.com/` HTML and its static frontend bundles,
with this repository's `App/Resources/ChatParity.json` messages, users and rooms.
It does not redraw H5 or replace its CSS/components. Browser traffic is restricted
to the loopback fixture origin. The server forwards only GETs for allowlisted
public static paths; APIs, account tokens and write requests are never forwarded.
Unknown API contracts fail with 501 rather than fake success.

## Run

```sh
cd scripts/h5-chat
npm ci --ignore-scripts
npx playwright install --with-deps chromium
npm run capture
```

`CHROMIUM_PATH` optionally selects an installed browser. `OUTPUT_DIR` selects a
local output directory. The current public HTML is downloaded once and hashed;
`H5_HTML` may select an explicit archived HTML file. The default cache is private
to this harness. Deliberate version updates require a fresh HTML/cache directory,
not unlabelled reuse of old bundled assets.

Eight cases: private/group × 375×667 / 440×956 CSS pixels × light/dark. Each case
must show a known last message, load its actual successful timeline endpoint and
real JS bundles, expose an onscreen textarea, match H5's actual theme, and have
zero unexpected runtime, console, failed-response or outbound-request errors.
A 404 from POST `/api/i/registry/get` is expected only when its parsed body
is exactly the `NO_SUCH_KEY` error code; its corresponding Chromium resource
console line is retained separately. Other errors on that path still fail. Only passing
cases write `h5-*.png`; failures write clearly named diagnostics, if rendering
was reached. The harness records geometry and API/asset provenance. Known initial
setup is dismissed through the actual Later + confirmation buttons, not hidden
with CSS. Focused captures are desktop Chromium focus, **not an iOS software
keyboard test**.

## Verification and comparison limits (2026-11-13)

The original C17 Linux browser attempt failed before opening a page with
`socket() failed: Operation not permitted (1)`. C17 CI's Ubuntu-latest browser
dependency step also failed before rendering: its image had moved to Ubuntu26.04.
Neither attempt is an H5 rendering pass. The next workflow pins Ubuntu24.04.

A separate Windows capture used existing Node/Python, Playwright1.62.1 and
Chromium156 without installing dependencies. It passed 8 cases and wrote 16
regular/focused images, with zero unexpected browser errors. Those tool versions
differ from the committed CI Playwright1.56.1 lockfile; each evidence report keeps
its actual versions, source hashes and timestamps. Initial Windows GBK failure
is retained separately from the successful UTF-8 run.

The initial H5 harness had a generic 1×1 avatar while native used the 320×180
`GIFTestFixtures.still`. That was NOT same-media evidence. `fixture_media.py` now
reads the exact native still/looping/finite/avatar literals; missing media fails instead
of substituting. Health/provenance records their hashes. Corrected Windows
captures were paired with original C17 small-native screenshots. The transparent
wide pink-dot fixture is a rendering probe, not a normal profile-photo corpus.
Native fixture fit vs production fill was a separate identified difference. C18
uses a dedicated128×128 opaque geometric avatar for both clients, with native
DEBUG fill matching production. Existing media probes remain unchanged. New
C18 screenshots must not be paired with older C17 avatar data.

Four small-screen private/group light/dark pairs were actually reviewed. P0 tools
are visible without the four-tab bar. Navigation, metadata spacing, date styles,
emoji and avatar geometry still differ. No numeric pixel-match score or 1:1
claim is made. H5 focus is NOT an iOS software keyboard. Native's actual device
record must be checked before pairing; no large-native comparison is established
by a large-browser screenshot alone.

Both clients use fixed synthetic messages, but relative times still use capture
wall time. The fixture is not a full MFM/media corpus. H5 fixture source and
bundle hashes must accompany screenshots; the unversioned local Vue snapshot is
not proven to equal a deployed source commit. Four-tab navigation is an approved
native difference, but must not occupy conversation tools.
