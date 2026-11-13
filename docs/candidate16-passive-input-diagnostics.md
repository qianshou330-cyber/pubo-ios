# C16 passive input diagnostics (runtime verification pending)

This is a diagnostic change, not a claim that C15 product or UI failures are fixed. No release behavior, fixture data, expected values, retry count, timeouts, OCR thresholds, CI gate dependencies or workflow selection change.

## Preserved C15 facts

C15 source fa4a829f350e2334151c98f3fbe42ca17e9d2b11, run 43413296058: core157 Swift/53 Python/2 Node passed. ChatAlignment small9/9 with zero skipped and successful whole job. Chat large and legacy small stopped before tests on simulator boot/shutdown timeouts. Both new-navigation jobs stopped at AX runner initialization: zero business methods, not13 failing assertions. Legacy large executed5:3 passed,2 failed. OCR retained its three known confidence-control failures; formal package skipped. No current-SHA full-coverage claim.

The privacy failure is the third transition, isLocked1 to0. Original XCSynthesizedEventRecord targets PID16246 at(370.5,177), the native switch center inside frame(339,163,63,28). The same PID logged earlier isLocked=true and autoAcceptFollowed=true but no isLocked=false; delayed original screenshots/AX still show1. hideOnlineStatus=true belongs to later PID51074 and must not be attributed to this event. Correct target dispatch does not prove delivery or a binding failure. Extending the wait, repeating tap, or changing the expected value would not establish the cause.

The refresh failure occurs waiting for generation2 immediately after the one pull gesture. Original synthesized event targets PID30037, from(426.8,191.2) to(426.8,822.16),0.1s hold/1.26192s movement. Seven passive diagnostic snapshots stay rowsApplied1/fixtureGeneration1/pullStarted0/background0. Thus the test never reached the background/resume step. It is not evidence that foreground resume failed; it is evidence that the expected pull-refresh result did not occur. The cause at gesture recognition/native refresh remains unresolved.

## What is added

- Privacy keeps one native tap and8-second observation budget. Each transition records expected/before, monotonic tap start/return, every real value read and query duration, and the final outcome. The same Foundation equality is evaluated on the read value, not on diagnostic descriptions. No later screenshot can retroactively fulfill the wait. Existing dependent enablement and retained-value checks stay intact.
- Refresh retains the original single gesture and10-second next-generation wait. Attachments record the pre-input screenshot, scroll geometry/hittability, generation target and dispatch/observation times. Missing generation remains an assertion failure.
- Existing timeline drag onEnded records only a fixed DEBUG counter, timelineDragEnded, through the already fixture-gated logger. No new recognizer, input synthesis, refresh trigger or state mutation is added. Release builds compile this call and logger out. A counter receipt only proves the existing callback ran, not that native refresh or a new generation occurred.
- Swift diagnostic checks cover the new counter and disabled flags; the existing128-line cap and release symbol absence checks remain. A Python negative test confirms the counter cannot substitute for post-resume row/generation increments. The strict lifecycle parser is unchanged.

This instrumentation may influence timing because evidence collection itself takes time. A later passing run alone would not prove a root-cause fix. Keep C15 failures and compare original events, same-process callback counters, value observations and exact counts. Physical camera, APNs, iOS17 and signed install/upgrade remain unverified. C16 is not a new user-visible feature candidate and should not cause a duplicate IPA delivery merely because another unsigned package is built.
