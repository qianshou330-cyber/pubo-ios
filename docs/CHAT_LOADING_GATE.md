# Deterministic synthetic loading-state test gate

C19 states-large failed because the five-second fixture response completed before
XCTest queried loading: synthesized tap at t=27.60, loading query at t=33.64.
The recording actually shows the spinner/loading text; later failure AX shows
chat.empty and the real empty message. This is a missed observation window, not
evidence the loading view was never rendered.

Only the loading-to-empty UI test now enables --chat-load-gate in the DEBUG
FixtureTransport. A unique per-launch UUID and private/room target travel via
launchEnvironment. The runner registers the Darwin name and state=0 before
launch; the matching conversation request asynchronously waits for state=1.
Real product loading UI is asserted within the unchanged three-second window and
captured before the runner releases the real fixture response. The existing
fifteen-second empty assertion remains, with loading absence also checked.
No accessibility marker, UI override, model-state injection, product endpoint,
production transport, or global timing change is involved. The old five-second
--chat-load-delay and fail-once test remain unchanged.

Darwin state is retained by the runner registration, so release cannot be lost
if app registration comes later. App polls every 50ms without blocking a thread,
checks cancellation and unregisters in defer. Invalid configuration, registration,
read, invalid state, and 120-second cleanup deadline throw instead of returning
an empty result. That deadline is not an assertion timeout or automatic success.
Runner initialization/release failures throw; exceptional defer cleanup is
best-effort release/unregister and App termination, never an assertion success.
UUID names separate launches and parallel simulator runs. No payload/user data
is posted.

## Verification boundary

Python source contracts do not prove Darwin inter-process behavior. Run
`scripts/check_chat_gate_macos.sh` on macOS before the actual UI gate. It compiles
the exact app/runner helpers and tests held response, release before registration,
and cancellation in separate local processes, without network or workflow changes.
This preflight does not prove iOS sandbox permissions; the actual iOS simulator
loading-to-empty test must still pass on both sizes. Current Linux environment
cannot compile the Darwin Swift imports or execute this preflight. API bridging,
notification-state sharing, and simulator permission behavior remain unverified.
