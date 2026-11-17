#if DEBUG
import Foundation

/// Passive synthetic-fixture lifecycle evidence; never installs an input handler.
final class ConversationDiagnostics {
    enum Event: String { case rowAppeared, rowDisappeared, destinationAppeared, destinationDisappeared }
    static let shared = ConversationDiagnostics(arguments: ProcessInfo.processInfo.arguments)
    private let enabled: Bool
    private let lock = NSLock()
    private var emitted = 0
    init(arguments: [String]) {
        enabled = arguments.contains("--ui-testing") && arguments.contains("--chat-align")
    }
    func record(_ event: Event) {
        guard enabled else { return }
        lock.lock(); defer { lock.unlock() }
        guard emitted < 128 else { return }
        emitted += 1
        print("PUBO_CONVERSATION_DIAG pid=\(ProcessInfo.processInfo.processIdentifier) uptime=\(ProcessInfo.processInfo.systemUptime) sequence=\(emitted) event=\(event.rawValue)")
    }
}
#endif
