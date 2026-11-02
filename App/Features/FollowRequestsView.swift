import SwiftUI
import PUBOCore

struct FollowRequestsView: View {
    @Environment(AppSession.self) private var session
    @State private var rows: [Record] = []
    @State private var error: String?
    @State private var busy = false
    @State private var acting = Set<String>()
    @State private var more = true
    var body: some View {
        List {
            ForEach(rows) { row in
                let user = Record(row["follower"])
                VStack(alignment: .leading, spacing: 10) {
                    NavigationLink { ProfileView(userID: user.id) } label: { HStack { Avatar(user: user); Text(user.displayName) } }
                    HStack { Button("接受") { Task { await respond(user, accept: true) } }; Spacer(); Button("拒绝", role: .destructive) { Task { await respond(user, accept: false) } } }.disabled(acting.contains(user.id))
                }
            }
            if rows.isEmpty && !busy && error == nil { Text("暂无关注申请") }
            if more && !rows.isEmpty { Button("加载更多") { Task { await load() } }.disabled(busy) }
            if let error { ErrorBanner(message: error) { Task { await load(reset: true) } } }
        }.puboList().navigationTitle("关注申请").task { await load(reset: true) }.refreshable { await load(reset: true) }
    }
    private func load(reset: Bool = false) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            var fields: [String: JSONValue] = ["limit": .number(30)]
            if !reset, let id = rows.last?.id { fields["untilId"] = .string(id) }
            let response = try await session.call("following/requests/list", fields); try Task.checkCancellation()
            guard case .array = response else { throw APIError.invalidResponse }
            rows = Records.merge(reset ? [] : rows, Record.list(response), limit: 5_000); more = response.array.count == 30; error = nil
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func respond(_ user: Record, accept: Bool) async {
        guard !acting.contains(user.id) else { return }; acting.insert(user.id); defer { acting.remove(user.id) }
        do { _ = try await session.call(accept ? "following/requests/accept" : "following/requests/reject", ["userId": .string(user.id)], mutation: true); rows.removeAll { $0["follower"]["id"].string == user.id }; await session.refreshUnread() }
        catch { self.error = "申请可能已由其他设备处理，请刷新后核对。" }
    }
}
