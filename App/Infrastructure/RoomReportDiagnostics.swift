#if DEBUG
import Foundation
import OSLog

/// Fixed stages and booleans only. Never logs message IDs, text, users or credentials.
@MainActor enum RoomReportDiagnostics {
    enum Event: String { case actionEntered, rejected, accepted, stateAssigned, statePresent, stateCleared, sheetAppeared, sheetDisappeared }
    static let enabled = ProcessInfo.processInfo.arguments.contains("--ui-testing") &&
        ProcessInfo.processInfo.arguments.contains("--chat-align") &&
        !ProcessInfo.processInfo.arguments.contains("--isolated-backend")
    private static let logger = Logger(subsystem: "com.pubo.roomreport.diagnostics", category: "action-sheet")
    private static var count = 0
    static func record(_ event: Event, flags: [Bool] = []) {
        guard enabled, count < 32 else { return }
        count += 1
        // Rejection order: active, foreground, messages section, no preview,
        // current epoch, current owner, current unrecalled exact message snapshot.
        let message = "event=\(event.rawValue) flags=\(flags) uptime=\(ProcessInfo.processInfo.systemUptime) pid=\(ProcessInfo.processInfo.processIdentifier)"
        logger.notice("\(message, privacy: .public)")
    }
}
#endif
