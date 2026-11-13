import Foundation
import Dispatch

let flags = ["--ui-testing", "--refreshable-feed"]
for args in [[], ["--ui-testing"], ["--refreshable-feed"]] {
    let disabled = RefreshDiagnostics(arguments: args)
    disabled.record(.pullStarted)
    disabled.record(.timelineDragEnded)
    precondition(disabled.snapshot().isEmpty)
}
let counter = RefreshDiagnostics(arguments: flags)
precondition(counter.snapshot().isEmpty)
counter.record(.captureStarted)
precondition(counter.snapshot()[.captureStarted] == 1)
counter.record(.pullStarted)
counter.record(.pullEnded)
counter.record(.timelineDragEnded)
precondition(counter.snapshot()[.timelineDragEnded] == 1)
precondition(counter.snapshot()[.pullStarted] == 1)
precondition(counter.snapshot()[.pullEnded] == 1)
DispatchQueue.concurrentPerform(iterations: 1_000) { _ in counter.record(.fixtureGeneration) }
precondition(counter.snapshot()[.fixtureGeneration] == 1_000)
precondition(RefreshDiagnostics(arguments: flags).snapshot().isEmpty)
// Existing 128-log cap does not prevent counting; no-op and pending-only
// responses must not masquerade as visible applications.
let merging = counter
merging.recordMergedPage(beforeVisible: ["a"], afterVisible: ["a"], beforePending: [], afterPending: [])
precondition(merging.snapshot()[.rowsApplied] == nil)
merging.recordMergedPage(beforeVisible: ["a"], afterVisible: ["a"], beforePending: [], afterPending: ["b"])
precondition(merging.snapshot()[.rowsApplied] == nil)
precondition(merging.snapshot()[.rowsPending] == 1)
merging.recordMergedPage(beforeVisible: ["a"], afterVisible: ["a", "b", "c"], beforePending: ["b"], afterPending: [])
precondition(merging.snapshot()[.rowsApplied] == 1)
precondition(merging.snapshot()[.rowsPending] == 1)
print("DIAGNOSTIC_TESTS_PASS")
