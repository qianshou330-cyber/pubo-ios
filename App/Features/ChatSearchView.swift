import SwiftUI
import PUBOCore

struct ChatSearchView: View {
    @Environment(AppSession.self) private var session
    var peer: Record?
    var roomID: String?
    var select: ((String) -> Void)?
    var embedded = false
    var selectMessage: ((Record) -> Void)?
    @State private var query = ""
    @State private var rows: [Record] = []
    @State private var error: String?
    @State private var busy = false
    private var content: some View {
        Group {
            TextField("搜索聊天文字", text: $query).submitLabel(.search).puboInput().accessibilityIdentifier("chat.search.query").puboListRow()
            Text("搜索结果不会标记消息已读。").font(.caption).foregroundStyle(.secondary)
            ForEach(rows) { row in
                if let selectMessage { Button { selectMessage(row) } label: { result(row) } }
                else if let select { Button { select(row.id) } label: { result(row) } }
                else if row["toRoomId"].isNull { NavigationLink { ChatSearchDestination(message: row) } label: { result(row) } }
                else if let room = row["toRoomId"].string { NavigationLink { RoomChatView(roomID: room, initialMessage: row) } label: { result(row) } }
            }
            if busy { ProgressView() }
            if rows.count == 100 { Text("已显示最近 100 条匹配记录，请缩小搜索范围。").font(.caption) }
            if let error { ErrorBanner(message: error) }
        }
    }
    var body: some View {
        Group {
            if embedded { content }
            else { List { content }.puboList().navigationTitle(roomID != nil ? "搜索本群" : (peer == nil ? "聊天搜索" : "搜索本会话")) }
        }.task(id: query) {
                rows = []; error = nil; busy = false
                guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                do {
                    try await Task.sleep(for: .milliseconds(350)); busy = true
                    var fields: [String: JSONValue] = ["query": .string(String(query.prefix(256))), "limit": .number(100)]
                    if let peer { fields["userId"] = .string(peer.id) }
                    if let roomID { fields["roomId"] = .string(roomID) }
                    let result = try await session.call("chat/messages/search", fields); try Task.checkCancellation()
                    guard case .array = result else { throw APIError.invalidResponse }; rows = Record.list(result); busy = false
                } catch { if !Task.isCancelled { busy = false; self.error = error.localizedDescription } }
            }
    }
    private func result(_ row: Record) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if let date = puboDate(row["createdAt"].string) { Text(date.formatted()).font(.caption).foregroundStyle(.secondary) }
            Text(row["recalledAt"].isNull ? row.text : "消息已撤回").lineLimit(4)
            if !row["attachments"].array.isEmpty { Text("包含附件").font(.caption) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(PUBOTheme.panel, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(PUBOTheme.divider, lineWidth: 1)).puboListRow()
    }
}

struct ChatSearchDestination: View {
    @Environment(AppSession.self) private var session
    let message: Record
    @State private var peer: Record?
    @State private var error: String?
    var body: some View {
        Group {
            if let peer { ChatView(peer: peer, initialMessageID: message.id) }
            else if let error { ErrorBanner(message: error) }
            else { ProgressView() }
        }.task {
            do {
                let id = message[message["fromUserId"].string == session.user?.id ? "toUserId" : "fromUserId"].string ?? ""
                guard !id.isEmpty else { throw APIError.invalidResponse }
                let user = Record(try await session.call("users/show", ["userId": .string(id)])); try Task.checkCancellation(); peer = user
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}
