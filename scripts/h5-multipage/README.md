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
