# Isolated SwiftPM watcher probe (not a product fix)

Purpose: test whether writes below a local Swift package root coincide with
additional Xcode package-graph work or delayed process exit. C57's stack alone
does not establish the triggering path.

Run on the same macOS/Xcode version as the failing CI, with `xcodegen` installed:

```sh
python3 probe.py --output "$RUNNER_TEMP/spm-probe" --budget 120
```

This creates a tiny macOS command-line executable and a local package at `.`.
It runs a 2 × 2 matrix: DerivedData inside/outside package root, and controlled
filesystem writes inside/outside package root. Every cell has identical source,
the same warm-build and measured-build commands, the same write schedule, and
the same hard process budget. Each cell gets a fresh fixture and package cache.
No PUBO source, UI assertion, simulator state, CI budget, or dependency is changed.

Retain the entire output directory. `summary.json` records command return codes,
timeouts, elapsed time and package-graph log markers. Per-cell writer JSONL gives
the actual paths and monotonic times. Xcode logs have timestamped lines. These
markers are NOT interpreted as pass/fail acceptance. A timeout remains a timeout.

Interpretation:
- Repeated extra package-graph work after inside writes, absent for matched
  outside writes, supports the watcher hypothesis in this fixture.
- A signal only when DerivedData is inside supports isolating generated output,
  but does not identify which real C57 file caused the event.
- No reproduction is inconclusive: a fast command-line build does not reproduce
  simulator test teardown or its long-running SwiftPM operation.
- Do not change PUBO paths on the strength of event coincidence alone. If the
  fixture produces a signal, repeat it in reverse order and then perform a single
  controlled PUBO run with the original selectors, expected count and 1800-second
  budget. Existing tests and xcodebuild exit status must still all succeed.

Linux validation is limited to Python unit tests and deterministic fixture and
command generation. Actual Xcode/FSEvents behavior is untested until macOS CI runs.

## Publication / CI wiring (parent only)
Files are private workspace candidates, not committed or run in CI.
Suggested destination for probe.py/test_probe.py: scripts/spm-watcher-probe/.
Install workflow-proposal.yml as .github/workflows/spm-watcher-probe.yml.
README may be retained with the scripts. This does not create a new product gate.

Latest parent-approved trigger wiring: workflow-proposal.yml now uses push limited
to ui-four-tabs-148-20261112 and this diagnostic workflow/script paths. The existing
full acceptance workflow also runs normally; no gate is bypassed. The diagnostic
runs forward then reverse serially on one runner, 120s per process, 40min outer cap.
DEVELOPER_DIR selects Xcode26.0.1 without altering system settings or using sudo.
Worker errors and finished status are explicit; writeCount records actual writes.
A trial with read/write errors or unfinished workers is invalid evidence, not a
negative finding. No consumer should equate diagnostic job success with product
acceptance, because timeout/failure outcomes are experimental data in summary.json.


Controlled writes start only after the observable Xcode line
\`Resolved source packages:\`, with a30-second marker wait limit. Missing marker or
process exit before pulses is recorded as insufficient experiment, not evidence
against the hypothesis. Actual write counts and thread errors are preserved.
Even this marker does NOT prove Xcode's filesystem observer is installed; it only
avoids writes known to precede package resolution. An unreproduced hang remains
inconclusive. Linux tests exercise this protocol, not actual observer readiness.

Frozen local validation:7Python tests pass, including missing marker ->zero writes.
