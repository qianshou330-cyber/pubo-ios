import Foundation

public struct PollDraft: Codable, Equatable, Sendable {
    public var choices: [String] = ["", ""]
    public var multiple = false
    public var expiresAt: Date?
    public init() {}
    public func request(now: Date = Date()) throws -> JSONValue {
        let clean = choices.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard (2...10).contains(clean.count), Set(clean).count == clean.count,
              clean.allSatisfy({ !$0.isEmpty && $0.unicodeScalars.count <= 50 }) else {
            throw APIError(code: "INVALID_POLL", message: "投票需要 2～10 个不重复的选项，每项最多 50 个字符。")
        }
        if let expiresAt, expiresAt <= now { throw APIError(code: "POLL_EXPIRED", message: "投票结束时间必须晚于现在。") }
        return .object(["choices": .strings(clean), "multiple": .bool(multiple),
                        "expiresAt": expiresAt.map { .number(floor($0.timeIntervalSince1970 * 1000)) } ?? .null])
    }
}

public enum SocialContent {
    /// Match the existing chat backend's emoji selector normalization; ZWJ sequences stay intact.
    public static func chatReactionKey(_ reaction: String) -> String {
        reaction.unicodeScalars.contains { $0.value == 0x200D } ? reaction : reaction.replacingOccurrences(of: "\u{FE0F}", with: "")
    }
    public static func pollReceipt(_ poll: JSONValue, request: JSONValue?) -> Bool {
        guard let request, !request.isNull else { return poll.isNull }
        guard poll["choices"].array.map({ $0["text"].string }) == request["choices"].array.map(\.string),
              poll["multiple"].bool == request["multiple"].bool else { return false }
        if request["expiresAt"].isNull { return poll["expiresAt"].isNull }
        guard let text = poll["expiresAt"].string, let date = date(text) else { return false }
        return abs(date.timeIntervalSince1970 * 1000 - Double(request["expiresAt"].int)) < 1
    }
    public static func date(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}

/// Chat snapshots can arrive out of order. A tombstone is never resurrected.
public enum ChatRecords {
    public static func merge(_ existing: [Record], _ incoming: [Record], missingIDs: [String] = []) -> [Record] {
        var values = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for item in incoming where !item.id.isEmpty {
            if let old = values[item.id] {
                if item["revision"].int < old["revision"].int || (!old["recalledAt"].isNull && item["recalledAt"].isNull) { continue }
                var merged = item.raw.object
                merged["replyTo"] = ChatReferences.newest(old["replyTo"], item["replyTo"])
                // The lightweight state endpoint omits participants; preserve known display fields.
                for key in ["fromUser", "toUser", "clientMessageId"] where merged[key] == nil { merged[key] = old[key] }
                if !old["readAt"].isNull && item["readAt"].isNull { merged["readAt"] = old["readAt"]; merged["readState"] = .string("read") }
                values[item.id] = Record(.object(merged))
            } else { values[item.id] = item }
        }
        for id in missingIDs { values.removeValue(forKey: id) }
        let sorted = values.values.sorted { $0.id < $1.id }
        return ChatReferences.reconcile(sorted, targets: sorted, missing: missingIDs)
    }
}
