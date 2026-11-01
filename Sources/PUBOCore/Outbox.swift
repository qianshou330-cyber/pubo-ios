import Foundation

public struct PendingChat: Codable, Equatable, Identifiable, Sendable {
    public enum State: String, Codable, Sendable { case ready, sending, uncertain, rejected }
    public let id: String
    public let recipientID: String
    public let text: String
    public let attachmentIDs: [String]
    public let replyToID: String?
    public let createdAt: Date
    public var state: State
    public var errorCode: String?

    public init(recipientID: String, text: String, attachmentIDs: [String] = [], replyToID: String? = nil) {
        id = UUID().uuidString
        self.recipientID = recipientID; self.text = text.trimmingCharacters(in: .whitespacesAndNewlines); self.attachmentIDs = attachmentIDs
        self.replyToID = replyToID; createdAt = Date(); state = .ready
    }
    public var payload: [String: JSONValue] {
        var result: [String: JSONValue] = ["toUserId": .string(recipientID), "clientMessageId": .string(id), "attachmentIds": .strings(attachmentIDs)]
        if !text.isEmpty { result["text"] = .string(text) }
        if let replyToID { result["replyToId"] = .string(replyToID) }
        return result
    }
    public func matches(_ message: Record, authorID: String) -> Bool {
        message["clientMessageId"].string == id && message["fromUserId"].string == authorID &&
        (message["toUserId"].string == nil || message["toUserId"].string == recipientID) &&
        message["replyToId"].string == replyToID && message.text == text &&
        message["attachments"].array.compactMap { $0["id"].string } == attachmentIDs
    }
}

public enum OutboxRecovery {
    public static func restore(_ items: [PendingChat], now: Date = Date()) -> [PendingChat] {
        items.filter { now.timeIntervalSince($0.createdAt) < 86_400 }.map {
            var item = $0
            if item.state == .sending { item.state = .uncertain }
            return item
        }
    }
}
