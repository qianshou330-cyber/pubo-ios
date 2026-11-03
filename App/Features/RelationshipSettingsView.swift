import SwiftUI
import PUBOCore

struct RelationshipSettingsView: View {
    @Environment(AppSession.self) private var session
    @State private var kind = "mute"
    @State private var rows: [Record] = []
    @State private var users: [String: Record] = [:]
    @State private var more = true
    @State private var busy = false
    @State private var picker = false
    @State private var adding: Record?
    @State private var selectedUser: Record?
    @State private var removing: Record?
    @State private var duration = 0
    @State private var error: String?
    @State private var revision = UUID()
    private var userKey: String { kind == "blocking" ? "blockee" : "mutee" }
    var body: some View {
        List {
            Picker("类型", selection: $kind) { Text("静音").tag("mute"); Text("转发静音").tag("renote-mute"); Text("屏蔽").tag("blocking"); Text("仅聊天屏蔽").tag("chat/blocking") }.disabled(busy)
            if kind == "mute" { Picker("新静音的时长", selection: $duration) { Text("持续生效").tag(0); Text("1 小时").tag(3600); Text("1 天").tag(86400); Text("7 天").tag(604800) } }
            Button("添加用户") { picker = true }.disabled(busy)
            ForEach(rows) { row in
                let target = target(row)
                HStack { NavigationLink { ProfileView(userID: target.id) } label: { HStack { Avatar(user: target); VStack(alignment: .leading) { Text(target.displayName); if let date = puboDate(row["expiresAt"].string) { Text("到期 " + date.formatted()).font(.caption) } } } }; Button("移除") { removing = row }.disabled(busy) }
            }
            if more { Button("加载更多") { Task { await load() } }.disabled(busy) }
            if let error { ErrorBanner(message: error) }
        }.puboForm().navigationTitle("静音与屏蔽").task(id: kind) { revision = UUID(); rows = []; users = [:]; more = true; await load() }
            .sheet(isPresented: $picker, onDismiss: { adding = selectedUser; selectedUser = nil }) { UserPicker { selectedUser = $0 } }
            .alert("确认对这个用户设置\(kind == "blocking" ? "屏蔽？屏蔽会影响关注关系。" : kind == "chat/blocking" ? "聊天屏蔽？" : "静音？")", isPresented: Binding(get: { adding != nil }, set: { if !$0 { adding = nil } }), presenting: adding) { user in
                Button("确认") { Task { await update(id: user.id, remove: false) } }
                Button("取消", role: .cancel) { adding = nil }
            }
            .alert("确认移除这项设置？", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), presenting: removing) { row in
                Button("确认移除", role: .destructive) { let id = target(row).id; Task { await update(id: id, remove: true) } }
                Button("取消", role: .cancel) { removing = nil }
            }
    }
    private func target(_ row: Record) -> Record { if kind == "chat/blocking" { return users[row["userId"].string ?? ""] ?? Record(.object(["id": row["userId"], "username": row["userId"]])) }; return Record(row[userKey]) }
    private func load() async {
        guard !busy else { return }; busy = true; defer { busy = false }; let request = revision; let selected = kind
        do {
            var fields: [String: JSONValue] = ["limit": .number(30)]; if let last = rows.last { fields["untilId"] = .string(last.id) }
            let page = Record.list(try await session.call(selected + "/list", fields)); try Task.checkCancellation(); guard request == revision else { return }
            if selected == "chat/blocking", !page.isEmpty { let people = Record.list(try await session.call("users/show", ["userIds": .array(page.map { $0["userId"] })])); guard request == revision else { return }; for user in people { users[user.id] = user } }
            rows = Records.merge(rows, page, limit: 10000); more = page.count == 30; error = nil
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func update(id: String, remove: Bool) async {
        guard !busy, !id.isEmpty else { return }; busy = true
        do {
            var fields: [String: JSONValue] = ["userId": .string(id)]; if kind == "mute", !remove { fields["expiresAt"] = duration == 0 ? .null : .number(floor(Date().addingTimeInterval(Double(duration)).timeIntervalSince1970 * 1000)) }
            _ = try await session.call(kind + (remove ? "/delete" : "/create"), fields, mutation: true)
            adding = nil; removing = nil; rows = []; more = true; busy = false; await load()
        } catch { busy = false; self.error = error.localizedDescription + " 请刷新列表核对结果后再操作。" }
    }
}

struct InvitationsView: View {
    @Environment(AppSession.self) private var session
    @State private var rows: [Record] = []
    @State private var remaining: JSONValue = .null
    @State private var more = true
    @State private var busy = false
    @State private var confirming = false
    @State private var removing: Record?
    @State private var uncertain = false
    @State private var error: String?
    var body: some View {
        List {
            Text(remaining.isNull ? "可用数量由本站角色规则决定" : "剩余可创建：\(remaining.int)")
            Button("创建邀请码") { confirming = true }.disabled(busy || uncertain || (!remaining.isNull && remaining.int == 0))
            Button("刷新列表") { Task { rows = []; more = true; await load() } }.disabled(busy)
            if uncertain { Text("上次创建结果未确认。请完整核对列表，避免重复创建。"); Button("我已核对，解除创建锁定") { uncertain = false; try? session.markPendingAction("invite-create", pending: false) } }
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 8) {
                    Text(row["code"].string ?? "邀请码").textSelection(.enabled).font(.headline)
                    Text(row["usedBy"].isNull && row["usedById"].isNull ? "未使用" : "已使用").font(.caption)
                    if let date = puboDate(row["expiresAt"].string) { Text("有效期至 " + date.formatted()).font(.caption) }
                    Button("删除邀请码", role: .destructive) { removing = row }.disabled(busy)
                }
            }
            if more { Button("加载更多") { Task { await load() } }.disabled(busy) }
            if let error { ErrorBanner(message: error) }
        }.puboForm().navigationTitle("邀请").privacySensitive().task { uncertain = session.hasPendingAction("invite-create"); await load() }
            .confirmationDialog("创建一个新的邀请码？", isPresented: $confirming) { Button("确认创建") { Task { await create() } } }
            .confirmationDialog("删除后此邀请码不能再使用。", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) { Button("确认删除", role: .destructive) { if let item = removing { Task { do { _ = try await session.call("invite/delete", ["inviteId": .string(item.id)], mutation: true); rows.removeAll { $0.id == item.id } } catch { self.error = error.localizedDescription } } } } }
    }
    private func load() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do { remaining = try await session.call("invite/limit")["remaining"]; var fields: [String: JSONValue] = ["limit": .number(30)]; if let last = rows.last { fields["untilId"] = .string(last.id) }; let page = Record.list(try await session.call("invite/list", fields)); rows = Records.merge(rows, page, limit: 10000); more = page.count == 30; error = nil } catch { self.error = error.localizedDescription }
    }
    private func create() async {
        guard !busy, !uncertain else { return }; busy = true; defer { busy = false }
        do { try session.markPendingAction("invite-create", pending: true); uncertain = true; let result = Record(try await session.call("invite/create", mutation: true)); guard !result.id.isEmpty, result["code"].string != nil else { throw APIError.uncertain }; rows = Records.merge([result], rows, limit: 10000); try session.markPendingAction("invite-create", pending: false); uncertain = false; remaining = try await session.call("invite/limit")["remaining"] }
        catch { if let apiError = error as? APIError, apiError.code != "OUTCOME_UNKNOWN" { try? session.markPendingAction("invite-create", pending: false); uncertain = false }; self.error = error.localizedDescription }
    }
}

struct AchievementsView: View {
    @Environment(AppSession.self) private var session
    @State private var rows: [JSONValue] = []
    @State private var error: String?
    var body: some View {
        List { ForEach(rows, id: \.self) { item in VStack(alignment: .leading) { Label(NativeStrings.achievement(item["name"].string ?? "成就"), systemImage: "medal"); Text(NativeStrings.achievement(item["name"].string ?? "", field: "description")).font(.caption).foregroundStyle(.secondary); if case .number(let milliseconds) = item["unlockedAt"] { Text(Date(timeIntervalSince1970: milliseconds / 1000), style: .date).font(.caption) } } }; if let error { ErrorBanner(message: error) } else if rows.isEmpty { Text("暂无已获得成就") } }
            .puboForm().navigationTitle("成就").task { do { if let user = session.user { rows = try await session.call("users/achievements", ["userId": .string(user.id)]).array } } catch { self.error = error.localizedDescription } }
    }
}
