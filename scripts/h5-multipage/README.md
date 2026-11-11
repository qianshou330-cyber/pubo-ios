# Isolated multipage H5 capture - EXPERIMENTAL, NOT VALIDATED

Separate from the current production capture harness. Pages attempted: channels/search,
empty Drive, profile settings, privacy settings. The browser never forwards API requests,
credentials, or writes to production. The server fetches public static bundles only.

Known synthetic read endpoints are explicitly enumerated. Unknown endpoints return 501.
`i/update` and other data mutations are deliberately unimplemented. Settings are viewed,
not changed. Local registry/achievement/onboarding bookkeeping is synthetic only.
Browser requests to any nonlocal origin are aborted. Uncaught errors, console errors,
HTTP errors and blocked requests invalidate the page rather than producing parity proof.

Dependencies: Playwright 1.56.1 from the parent lockfile. In CI use the same official
versioned Playwright container as the established 142 visual-reference job.

Run from a suitable environment:

```
FIXTURE_PATH=/absolute/path/to/TimelineParity.json node capture.mjs
```

Current capture script resolves the fixture from `../../App/Resources/TimelineParity.json`
unless overridden with FIXTURE_PATH. For system Chromium set CHROMIUM_PATH explicitly.
Output goes to `artifacts`; public asset cache is under `cache`.

## Actual attempt

2026-11-11: default cloud shell Chromium could not launch: UNIX socket creation returned
`Operation not permitted`. A permitted elevated retry encountered the same restriction.
No page capture succeeded, no test browser reached synthetic or production APIs.
No resulting image should be treated as evidence. The selectors and additional fixture
shapes still require real CI verification before use; do not declare them complete.

Do not copy cache, node_modules or artifacts into source control. Copy only audited
server.py, capture.mjs, package files and this documentation for an experiment.

## Strengthened capture and server audit

- Process exit is 1 on any failed/missing case, 0 only for all four passing pages.
- Known success-image names are cleared before a run; diagnostics have NOT-PARITY names.
- Each page requires its route, actual JS bundles, light theme and page-specific evidence.
  Channels must perform real UI search and load a synthetic result. Drive requires both
  file/folder API calls and the true empty state. Profile requires its real birthday and
  location inputs plus textarea. Privacy labels must have adjacent checkbox controls.
- Network errors, external request attempts, runtime and console errors invalidate captures.
- Server audit (`node audit-server.mjs`) passed nine local HTTP/CSP checks. Write endpoints
  and unknown APIs return 501, GET APIs return 405 and unknown HTML routes return 404.
- Static fetch audit: only two upstream fetch sites exist, the public bolubo.com homepage
  and a fixed-origin static-prefix GET. Redirects are forbidden; API POST handlers do not
  call upstream fetch. No incoming auth headers or body are reused in static GETs.
- Integrating into `scripts/h5-multipage`: pass
  `FIXTURE_PATH=../../App/Resources/TimelineParity.json`. Use Playwright 1.56.1 container.
  `OUTPUT_DIR` and `PORT` can be configured; keep node_modules/cache/artifacts untracked.

These assertions are intentionally strict and may reveal additional missing local fixtures
in CI. Such failure is a diagnostic, not permission to suppress errors or use placeholder UI.

## 145 evidence-recovery follow-up

The isolated recovery run reached a different channel failure: the initial featured API
had not been observed at the fixed 12-second preflight. The harness now waits, for at
most 90 seconds, for the real successful POST response before proving page content.
It does not make the request itself, suppress errors, synthesize a response, or waive
the featured-result/search-control checks. A missing API still fails the capture.
This is a readiness-race mitigation, not a confirmed explanation of that CI failure.

The existing late-onboarding handler uses the real Later action and its specific
confirmation. It never removes the overlay or forces clicks through it. All existing
route, bundle, theme, network and page-specific proof checks remain mandatory.
Local syntax/diff checks passed; Chromium could not launch because socket creation
is restricted in this executor. Real browser validation must run in the isolated CI.

The build 146 run observed the featured API but the delayed setup dialog still
intercepted the search-tab click; no locator-handler dismissal was recorded. Recovery
now checks the setup's real visible Later button explicitly and retries the normal
search click at most three times (3-second timeout per attempt). Only a timeout with
that known setup button visible permits a retry, after normal Later and confirmation
clicks. Other errors/overlays fail immediately. This replaces the ineffective automatic
locator handler; search API success and result checks are unchanged. CI validation is
still required before reporting successful channel capture.
