# Build 146: regression closure, not full parity acceptance

Base: build145 34a4bec. No new feature-page batch.

145 recovered evidence: backend21/21 passed, large native28/31 with failures in contact refresh, request confirmation and request refresh. Large screenshot artifact upload failed; counts come from original job logs, not a reconstructed image. Small retry is still running.

Changes:
- Separate follow-request navigation and action hit behavior in List rows with explicit button styles and44pt targets.
- Expose refresh actions while initial loading or existing rows remain visible; use real controls for the race tests rather than an unverified global swipe.
- DEBUG fixture response barriers wait for a second read or mutation, with45-second failure deadline, so concurrency assertions cannot accidentally run after the old response naturally completed.
- Await actual successful H5 featured/Drive API responses after genuine onboarding handling. No direct fixture API triggering or invented screenshots.
- Include run attempt in artifact names so future retries preserve evidence without colliding with original artifacts.

Local checks: Python packaging6/6, JS syntax and diff checks. Swift compilation and both device-size UI suites must still run on Mac CI. No main merge, PR, release or production API write.
