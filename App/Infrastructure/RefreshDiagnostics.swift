#if DEBUG
import Foundation
#if canImport(os)
import os
#endif

/// Passive fixture-only diagnostics. No UI nodes, gesture handlers or request data.
final class RefreshDiagnostics {
    enum Event: String, CaseIterable {
        case pullStarted, pullEnded, loadAttempt, skippedError, skippedBusy, skippedEnd
        case requestStarted, requestReturned, rowsApplied, rowsPending, loadFailed, cancelledResult, staleResult
        case fixtureGeneration, captureStarted, sceneBackground, sceneActive
    }
    static let shared = RefreshDiagnostics(arguments: ProcessInfo.processInfo.arguments)
    #if canImport(os)
    private let logger = Logger(subsystem: "com.pubo.refresh.diagnostics", category: "refresh")
    #endif
    private let enabled: Bool
    private let lock = NSLock()
    private var counts: [Event: Int] = [:]
    private var emitted = 0
    init(arguments: [String]) {
        enabled = arguments.contains("--ui-testing") && arguments.contains("--refreshable-feed")
    }
    /// Fixed enums and counts only; capped at 128 output lines per process.
    func record(_ event: Event) {
        guard enabled else { return }
        lock.lock(); defer { lock.unlock() }
        counts[event, default: 0] += 1
        if emitted < 128 {
            emitted += 1
            let message = "PUBO_REFRESH_DIAG " + Event.allCases.map { "\($0.rawValue)=\(counts[$0, default: 0])" }.joined(separator: ";")
            print(message)
            #if canImport(os)
            logger.notice("\(message, privacy: .public)")
            #endif
        }
    }
    /// Passive evidence of a merge, not merely a successful response. One event
    /// per applied response, regardless of row count; never logs note IDs.
    func recordMergedPage(beforeVisible: Set<String>, afterVisible: Set<String>,
                          beforePending: Set<String>, afterPending: Set<String>) {
        if !afterVisible.subtracting(beforeVisible).isEmpty { record(.rowsApplied) }
        if !afterPending.subtracting(beforePending).isEmpty { record(.rowsPending) }
    }
    func snapshot() -> [Event: Int] {
        lock.lock(); defer { lock.unlock() }
        return counts
    }
}
#endif
