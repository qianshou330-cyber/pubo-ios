import Foundation
import Observation
import PUBOCore

@MainActor @Observable final class ChatHomeState {
    private(set) var rows: [ChatConversation] = []
    private(set) var busy = false
    private(set) var hasMore = true
    private(set) var error: String?
    private var cursor: String?
    private var epoch = UUID()
    private var account: String?

    func invalidate() { epoch = UUID(); busy = false }
    func clear() { invalidate(); rows = []; cursor = nil; hasMore = true; error = nil; account = nil }
    func load(_ session: AppSession, older: Bool = false) async {
        if account != session.user?.id { rows = []; cursor = nil; hasMore = true; account = session.user?.id; invalidate() }
        guard !busy, !older || hasMore else { return }
        busy = true; let attempt = epoch; defer { if attempt == epoch { busy = false } }
        let viewer = session.user?.id ?? ""
        var fields: [String: JSONValue] = ["limit": .number(30), "pinned": .bool(false)]
        if older, let cursor { fields["untilId"] = .string(cursor) }
        let requestFields = fields
        async let ordinary = fetch(session, "chat/conversations", requestFields)
        async let pins = fetch(session, "chat/conversations", ["limit": .number(10), "pinned": .bool(true)])
        async let groups = fetch(session, "chat/history", ["room": .bool(true), "limit": .number(10)])
        let responses = await (ordinary, pins, groups)
        guard attempt == epoch, account == session.user?.id, !Task.isCancelled else { return }
        var failures: [String] = []
        func values(_ result: Result<[JSONValue], Error>, _ title: String) -> [JSONValue]? {
            switch result { case .success(let rows): return rows; case .failure(let issue): failures.append(title + "：" + issue.localizedDescription); return nil }
        }
        var direct = values(responses.0, "会话")
        let pinned = values(responses.1, "置顶"), rooms = values(responses.2, "群聊")
        var tail = direct ?? []
        let previousHead = rows.filter { $0.kind == .user && $0.pinnedAt == nil }.map { $0.message.id }.max()
        // Fill a burst of new conversations back to the known head before retaining older pages.
        // If interrupted, continue from this new tail on the next explicit pagination request.
        var reachedHistory = previousHead == nil || older
        if !older, let previousHead, direct != nil {
            for _ in 0..<10 {
                guard attempt == epoch, !Task.isCancelled else { return }
                guard tail.count == 30, let last = tail.last?["lastMessage"]["id"].string, last > previousHead else { reachedHistory = true; break }
                let next = values(await fetch(session, "chat/conversations", ["limit": .number(30), "pinned": .bool(false), "untilId": .string(last)]), "会话续页")
                guard let next else { break }
                guard next.last?["lastMessage"]["id"].string != last else { break }
                direct?.append(contentsOf: next); tail = next
            }
        }
        guard attempt == epoch, account == session.user?.id, !Task.isCancelled else { return }
        let hadCursor = cursor != nil
        if direct != nil, older || !hadCursor || !reachedHistory {
            cursor = tail.last?["lastMessage"]["id"].string
            hasMore = tail.count == 30
        }
        rows = ChatConversation.merge(rows, ordinary: direct?.compactMap(ChatConversation.direct), pins: pinned?.compactMap(ChatConversation.direct), rooms: rooms?.compactMap { ChatConversation.room($0, viewer: viewer) })
        error = failures.isEmpty ? nil : failures.joined(separator: "\n")
    }
    private func fetch(_ session: AppSession, _ endpoint: String, _ fields: [String: JSONValue]) async -> Result<[JSONValue], Error> {
        do { let result = try await session.call(endpoint, fields); try Task.checkCancellation(); guard case .array = result else { throw APIError.invalidResponse }; return .success(result.array) }
        catch { return .failure(error) }
    }
}
