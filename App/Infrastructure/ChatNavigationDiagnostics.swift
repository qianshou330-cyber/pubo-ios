#if DEBUG
import Foundation
import OSLog

/// Passive synthetic observations only. NavigationPath does not necessarily
/// include destination-based NavigationLinks. No touch-delivery claim is made.
@MainActor enum ChatNavigationDiagnostics {
    private static let enabled = ProcessInfo.processInfo.arguments.contains("--ui-testing") &&
        ProcessInfo.processInfo.arguments.contains("--chat-align") &&
        ProcessInfo.processInfo.arguments.contains("--four-tabs-drafts") &&
        !ProcessInfo.processInfo.arguments.contains("--isolated-backend")
    private static let logger = Logger(subsystem: "com.pubo.chatnavigation.diagnostics", category: "lifecycle")
    private static var emitted = 0
    enum Event: String { case privateTaskEntered, privatePeerReturned, privateDisappear, messagesPathChanged, leasesChanged, keyboardVisible, keyboardHidden }
    static func record(_ event: Event, session: AppSession, previousDepth: Int = -1) {
        guard enabled, emitted < 128 else { return }
        emitted += 1
        // Counts/booleans only: never routes, peer IDs, account IDs or text.
        let selectedLeases = session.conversationTabLeases.values.filter { $0 == session.selectedTab }.count
        let message = "event=\(event.rawValue) sequence=\(emitted) pid=\(ProcessInfo.processInfo.processIdentifier) uptime=\(ProcessInfo.processInfo.systemUptime) pathDepth=\(session.messagesPath.count) previousDepth=\(previousDepth) leaseCount=\(session.conversationTabLeases.count) selectedLeaseCount=\(selectedLeases) selectedMessages=\(session.selectedTab == .messages) hidesTabs=\(session.hidesBottomTabs) cancelled=\(Task.isCancelled) capReached=\(emitted == 128)"
        logger.notice("\(message, privacy: .public)")
    }
}
#endif
