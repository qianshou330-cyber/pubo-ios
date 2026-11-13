#if DEBUG
import Foundation
import Darwin

/// Test-only transport synchronization; never supplies or changes UI state.
enum ChatFixtureResponseGate {
    static func wait(path: String, environment: [String: String] = ProcessInfo.processInfo.environment) async throws {
        guard let nonce = environment["PUBO_CHAT_GATE_NONCE"], UUID(uuidString: nonce) != nil,
              let target = environment["PUBO_CHAT_GATE_TARGET"], ["private", "room"].contains(target) else {
            throw failure("configuration")
        }
        let expected = target == "private" ? "chat/messages/user-timeline" : "chat/messages/room-timeline"
        guard path == expected else { return }
        let name = "com.bolubo.fixture.chat-loading." + nonce
        var token: Int32 = 0
        guard notify_register_check(name, &token) == NOTIFY_STATUS_OK else { throw failure("register") }
        defer { notify_cancel(token) }
        let deadline = ProcessInfo.processInfo.systemUptime + 120
        while true {
            try Task.checkCancellation()
            var state: UInt64 = 0
            guard notify_get_state(token, &state) == NOTIFY_STATUS_OK else { throw failure("read") }
            if state == 1 { return }
            guard state == 0 else { throw failure("invalid-state") }
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw failure("timeout") }
            try await Task.sleep(for: .milliseconds(50))
        }
    }
    private static func failure(_ operation: String) -> NSError {
        NSError(domain: "PUBOChatFixtureGate", code: 1, userInfo: [NSLocalizedDescriptionKey: "Synthetic chat response gate failed: " + operation])
    }
}
#endif
