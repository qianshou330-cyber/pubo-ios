import Foundation
import Darwin

/// Retains the notification registration from before launch through response release.
/// Each launch owns a distinct name; no app UI or accessibility value is fabricated.
final class ChatLoadingTestGate {
    private let name: String
    private var token: Int32?
    let environment: [String: String]
    init(room: Bool) throws {
        let nonce = UUID().uuidString
        name = "com.bolubo.fixture.chat-loading." + nonce
        environment = ["PUBO_CHAT_GATE_NONCE": nonce, "PUBO_CHAT_GATE_TARGET": room ? "room" : "private"]
        var value: Int32 = 0
        try Self.check(notify_register_check(name, &value), "register")
        do { try Self.check(notify_set_state(value, 0), "initialize") }
        catch { notify_cancel(value); throw error }
        token = value
    }
    func release() throws {
        guard let token else { throw NSError(domain: "PUBOChatTestGate", code: 1, userInfo: [NSLocalizedDescriptionKey: "Gate is closed"]) }
        try Self.check(notify_set_state(token, 1), "release-state")
        try Self.check(notify_post(name), "release-notification")
    }
    func close() {
        guard let token else { return }
        // Best-effort exceptional cleanup only. Normal release errors are thrown above.
        notify_set_state(token, 1)
        notify_post(name)
        notify_cancel(token)
        self.token = nil
    }
    deinit { close() }
    private static func check(_ status: UInt32, _ operation: String) throws {
        guard status == NOTIFY_STATUS_OK else {
            throw NSError(domain: "PUBOChatTestGate", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Darwin gate " + operation + " failed"])
        }
    }
}
