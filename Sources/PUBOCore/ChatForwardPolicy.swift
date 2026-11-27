import Foundation

/// Forwarding delivery mode chosen in the friend picker sheet.
public enum ChatForwardMode: String, CaseIterable, Identifiable, Sendable {
    case oneByOne
    case combined

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .oneByOne: return "逐条转发"
        case .combined: return "合并文字"
        }
    }
}

/// Multi-select state for 1-on-1 chat messages with a strict 10-message upper bound.
public struct ChatSelectionState: Equatable, Sendable {
    public static let maxSelectionCount = 10

    public private(set) var selectedIDs: Set<String> = []

    public init() {}

    public var count: Int { selectedIDs.count }
    public var isEmpty: Bool { selectedIDs.isEmpty }
    public var isAtLimit: Bool { selectedIDs.count >= Self.maxSelectionCount }

    public func contains(_ id: String) -> Bool {
        selectedIDs.contains(id)
    }

    public enum ToggleOutcome: Equatable, Sendable {
        case selected(count: Int)
        case deselected(count: Int)
        case limitReached(max: Int)
        case ineligibleRecalled
    }

    @discardableResult
    public mutating func toggle(_ message: Record) -> ToggleOutcome {
        guard !message.id.isEmpty, message["recalledAt"].isNull else {
            return .ineligibleRecalled
        }
        if selectedIDs.contains(message.id) {
            selectedIDs.remove(message.id)
            return .deselected(count: selectedIDs.count)
        }
        guard selectedIDs.count < Self.maxSelectionCount else {
            return .limitReached(max: Self.maxSelectionCount)
        }
        selectedIDs.insert(message.id)
        return .selected(count: selectedIDs.count)
    }

    @discardableResult
    public mutating func selectInitial(_ message: Record) -> ToggleOutcome {
        selectedIDs.removeAll()
        return toggle(message)
    }

    public mutating func clear() {
        selectedIDs.removeAll()
    }

    /// Removes recalled or disappeared IDs and returns selected messages in original timeline chronological order.
    @discardableResult
    public mutating func pruneAndOrdered(from timeline: [Record]) -> [Record] {
        let aliveIDs = Set(timeline.filter { $0["recalledAt"].isNull }.map(\.id))
        selectedIDs.formIntersection(aliveIDs)
        return timeline.filter { selectedIDs.contains($0.id) }
    }
}

public struct ChatForwardAttachmentSummary: Equatable, Sendable {
    public let totalAttachments: Int
    public let oversizeCount: Int
    public let fallbackCount: Int
    public let voiceCount: Int

    public var forwardableCount: Int { max(0, totalAttachments - oversizeCount) }
    public var hasForwardableAttachments: Bool { forwardableCount > 0 }
    public var hasSkippedAttachments: Bool { oversizeCount > 0 || fallbackCount > 0 }
}

public enum ChatForwardError: LocalizedError, Equatable, Sendable {
    case noMessages
    case combinedTooLong(actual: Int, limit: Int)
    case recipientIneligible(String)

    public var errorDescription: String? {
        switch self {
        case .noMessages:
            return "所选消息均已撤回或不可转发。"
        case .combinedTooLong(let actual, let limit):
            return "合并转发正文共 \(actual) 字，超过单条 \(limit) 字上限，请改用「逐条转发」或减少条数。"
        case .recipientIneligible(let reason):
            return reason
        }
    }
}

/// Pure planning, formatting and recipient-eligibility logic for direct-chat message forwarding.
public enum ChatForwardPlanner {
    public static let maxTextLength = 2_000
    public static let maxAttachmentBytes = 50 * 1024 * 1024

    public static func eligibleRecipientProblem(account: Record?, viewerID: String?, recipient: Record) -> String? {
        if let base = ChatEligibility.problem(account: account, peer: recipient) {
            return base
        }
        guard !recipient.id.isEmpty else { return "无效的好友账号。" }
        if let viewerID, recipient.id == viewerID {
            return "不能转发消息给自己。"
        }
        return nil
    }

    public static func inspectAttachments(in messages: [Record]) -> ChatForwardAttachmentSummary {
        var total = 0
        var oversize = 0
        var fallback = 0
        var voice = 0
        for message in messages where message["recalledAt"].isNull {
            let files = Record.list(message["attachments"])
            for file in files {
                total += 1
                if file["size"].int > maxAttachmentBytes { oversize += 1 }
                if file["kind"].string == "voice" { voice += 1 }
            }
            if message["privateAttachmentFallback"].bool {
                fallback += 1
            }
        }
        return ChatForwardAttachmentSummary(
            totalAttachments: total,
            oversizeCount: oversize,
            fallbackCount: fallback,
            voiceCount: voice
        )
    }

    public static func senderName(for message: Record, viewerID: String?, viewerName: String, peerName: String) -> String {
        if let viewerID, message["fromUserId"].string == viewerID {
            return viewerName.isEmpty ? "我" : viewerName
        }
        if let embedded = message["fromUser"]["name"].string, !embedded.isEmpty {
            return embedded
        }
        if let username = message["fromUser"]["username"].string, !username.isEmpty {
            return username
        }
        return peerName.isEmpty ? "好友" : peerName
    }

    public static func attachmentPlaceholder(for attachment: Record) -> String {
        if attachment["kind"].string == "voice" { return "[语音]" }
        let mime = attachment["mime"].string ?? ""
        if mime == "image/gif" { return "[表情包]" }
        if mime.hasPrefix("image/") { return "[图片]" }
        if mime.hasPrefix("video/") { return "[视频]" }
        if mime.hasPrefix("audio/") { return "[音频]" }
        let name = attachment["name"].string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "[文件]" : "[文件：\(name)]"
    }

    public static func lineSummary(for message: Record) -> String {
        var parts: [String] = []
        let body = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty { parts.append(body) }
        for file in Record.list(message["attachments"]) {
            parts.append(attachmentPlaceholder(for: file))
        }
        if message["privateAttachmentFallback"].bool {
            parts.append("[网页附件]")
        }
        return parts.isEmpty ? "[消息]" : parts.joined(separator: " ")
    }

    public static func buildCombinedText(
        messages: [Record],
        peerName: String,
        viewerID: String?,
        viewerName: String,
        limit: Int = maxTextLength
    ) -> Result<String, ChatForwardError> {
        let alive = messages.filter { $0["recalledAt"].isNull }
        guard !alive.isEmpty else { return .failure(.noMessages) }
        let titlePeer = peerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "好友" : peerName
        var lines = ["转发自与 \(titlePeer) 的聊天记录（\(alive.count) 条）："]
        for message in alive {
            let sender = senderName(for: message, viewerID: viewerID, viewerName: viewerName, peerName: titlePeer)
            lines.append("「\(sender)」\(lineSummary(for: message))")
        }
        let combined = lines.joined(separator: "\n")
        let length = combined.unicodeScalars.count
        guard length <= limit else {
            return .failure(.combinedTooLong(actual: length, limit: limit))
        }
        return .success(combined)
    }

    public static func buildCopyText(
        messages: [Record],
        peerName: String,
        viewerID: String?,
        viewerName: String
    ) -> String {
        let alive = messages.filter { $0["recalledAt"].isNull }
        let textRows = alive.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !textRows.isEmpty else { return "" }
        if textRows.count == 1 {
            return textRows[0].text
        }
        let titlePeer = peerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "好友" : peerName
        return textRows.map { message in
            let sender = senderName(for: message, viewerID: viewerID, viewerName: viewerName, peerName: titlePeer)
            return "\(sender)：\(message.text)"
        }.joined(separator: "\n")
    }

    /// Removes self, deduplicates across recent + following (recent wins), and filters by query.
    public static func deduplicateRecipients(
        recent: [Record],
        following: [Record],
        viewerID: String?,
        query: String
    ) -> (recent: [Record], following: [Record]) {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        func matches(_ user: Record) -> Bool {
            guard !user.id.isEmpty, user.id != viewerID else { return false }
            guard !needle.isEmpty else { return true }
            let name = user.displayName.lowercased()
            let username = (user["username"].string ?? "").lowercased()
            return name.contains(needle) || username.contains(needle)
        }
        var seen = Set<String>()
        var uniqueRecent: [Record] = []
        for user in recent where matches(user) && seen.insert(user.id).inserted {
            uniqueRecent.append(user)
        }
        var uniqueFollowing: [Record] = []
        for user in following where matches(user) && seen.insert(user.id).inserted {
            uniqueFollowing.append(user)
        }
        return (uniqueRecent, uniqueFollowing)
    }
}
