#if DEBUG
import Foundation
import PUBOCore
import PUBONotify

/// Exists only in DEBUG. The task-local is process-local attribution, never an HTTP field.
enum C99WorldOrigin {
    enum Source: Sendable { case initial, retry }
    @TaskLocal static var source: Source?
    static let enabled: Bool = {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("--ui-testing") && args.contains("--c99-world-retry") && !args.contains("--isolated-backend")
    }()
}

/// Single writer of the phase latch. Runner owns a separate one-way release latch.
/// A request in the wrong phase permanently invalidates this launch, even during an actor suspension.
actor C99WorldRetryProbe {
    private enum Phase: UInt64 { case fresh = 0, failed503, held, recovered, invalid }
    private var phase: Phase = .fresh

    private func channel(_ side: String, _ nonce: String, _ action: (Int32) throws -> Void) throws {
        var token: Int32 = 0
        guard notify_register_check("com.bolubo.fixture.c99world." + nonce + "." + side, &token) == NOTIFY_STATUS_OK
        else { throw APIError.invalidResponse }
        defer { notify_cancel(token) }
        try action(token)
    }
    private func mark(_ next: Phase, _ nonce: String) throws {
        phase = next
        try channel("phase", nonce) { token in
            guard notify_set_state(token, next.rawValue) == NOTIFY_STATUS_OK else { throw APIError.invalidResponse }
        }
    }
    private func released(_ nonce: String) throws -> Bool {
        var state: UInt64 = 0
        try channel("release", nonce) { token in
            guard notify_get_state(token, &state) == NOTIFY_STATUS_OK, state <= 1 else { throw APIError.invalidResponse }
        }
        return state == 1
    }
    func respond(_ request: URLRequest, body: JSONValue) async throws -> (Data, HTTPURLResponse) {
        guard let nonce = ProcessInfo.processInfo.environment["PUBO_C99_WORLD_NONCE"],
              let uuid = UUID(uuidString: nonce), uuid.uuidString == nonce else { throw APIError.invalidResponse }
        let expected: JSONValue = .object(["limit": .number(20), "withRenotes": .bool(true),
                                           "withFiles": .bool(false), "withReplies": .bool(false), "i": .string("synthetic-session")])
        func reply(_ status: Int, _ payload: JSONValue) throws -> (Data, HTTPURLResponse) {
            guard let url = request.url, let http = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]) else { throw APIError.invalidResponse }
            return (try JSONEncoder().encode(payload), http)
        }
        do {
            let expectedURL = try Endpoint.api("notes/local-timeline")
            guard request.url == expectedURL, request.httpMethod == "POST",
                  request.value(forHTTPHeaderField: "Content-Type") == "application/json", body == expected
            else { throw APIError.invalidResponse } // exact body excludes every cursor, including a null one
            switch (phase, C99WorldOrigin.source) {
            case (.fresh, .initial?):
                guard try !released(nonce) else { throw APIError.invalidResponse }
                let result = try reply(503, .object(["error": .object(["code": .string("C99_LOCAL_503")])]))
                try mark(.failed503, nonce)
                return result
            case (.failed503, .retry?):
                guard try !released(nonce) else { throw APIError.invalidResponse }
                try mark(.held, nonce)
                let deadline = ProcessInfo.processInfo.systemUptime + 120
                while try !released(nonce) {
                    try Task.checkCancellation()
                    guard phase == .held, ProcessInfo.processInfo.systemUptime < deadline else { throw APIError.invalidResponse }
                    try await Task.sleep(for: .milliseconds(50))
                }
                try Task.checkCancellation()
                guard phase == .held else { throw APIError.invalidResponse }
                // Records.merge sorts by descending ID. The unique receipt must be the first visible row.
                let normalizedNonce: String = nonce.replacingOccurrences(of: "-", with: "").lowercased()
                let prefix: Substring = normalizedNonce.dropLast()
                var rows: [JSONValue] = []
                for index in 1...5 {
                    let id: String = String(prefix) + String(6 - index)
                    let text: String = index == 1 ? "推荐时间线已恢复" : "合成帖子 " + String(index)
                    var fields: [String: JSONValue] = [:]
                    fields["id"] = JSONValue.string(id)
                    fields["text"] = JSONValue.string(text)
                    fields["user"] = FixtureTransport.peer
                    fields["files"] = JSONValue.array([])
                    fields["reactions"] = JSONValue.object([:])
                    fields["createdAt"] = JSONValue.string("2026-11-01T12:00:00Z")
                    fields["visibility"] = JSONValue.string("public")
                    rows.append(JSONValue.object(fields))
                }
                let result = try reply(200, .array(rows))
                try mark(.recovered, nonce)
                return result
            default: throw APIError.invalidResponse // includes unmarked reconnect, duplicate, stale or wrong-origin requests
            }
        } catch {
            try mark(.invalid, nonce)
            throw error
        }
    }
}
#endif
