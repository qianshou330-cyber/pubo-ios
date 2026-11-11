import Foundation
import Dispatch

let flags = ["--ui-testing", "--refreshable-feed"]
for args in [[], ["--ui-testing"], ["--refreshable-feed"]] {
    let disabled = RefreshDiagnostics(arguments: args)
    disabled.record(.pullStarted)
    precondition(disabled.snapshot().isEmpty)
}
let counter = RefreshDiagnostics(arguments: flags)
precondition(counter.snapshot().isEmpty)
counter.record(.captureStarted)
precondition(counter.snapshot()[.captureStarted] == 1)
counter.record(.pullStarted)
counter.record(.pullEnded)
precondition(counter.snapshot()[.pullStarted] == 1)
precondition(counter.snapshot()[.pullEnded] == 1)
DispatchQueue.concurrentPerform(iterations: 1_000) { _ in counter.record(.fixtureGeneration) }
precondition(counter.snapshot()[.fixtureGeneration] == 1_000)
precondition(RefreshDiagnostics(arguments: flags).snapshot().isEmpty)
print("DIAGNOSTIC_TESTS_PASS")
