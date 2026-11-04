import SwiftUI
import PUBOCore

struct RoomsView: View {
    @Environment(AppSession.self) private var session
    var fixedSection: String? = nil
    var embedded = false
    @State private var selectedSection = "joining"
    private var section: String { fixedSection ?? selectedSection }
    @State private var rows: [Record] = []
    @State private var hasMore = false
    @State private var busy = false
    @State private var error: String?
    @State private var creating = false
    private var endpoint: String { section == "invited" ? "chat/rooms/invitations/inbox" : "chat/rooms/" + section }
    var body: some View {
        List {
            if fixedSection == nil { Picker("群聊分类", selection: $selectedSection) { Text("已加入").tag("joining"); Text("我创建的").tag("owned"); Text("邀请").tag("invited") }.pickerStyle(.segmented) }
            ForEach(rows) { row in
                let room = section == "owned" ? row : Record(row["room"])
                NavigationLink { RoomChatView(roomID: room.id) } label: { VStack(alignment: .leading) { Text(room["name"].string ?? "群聊"); Text(room["description"].string ?? "").lineLimit(2).font(.caption).foregroundStyle(.secondary) } }
            }
            if busy { ProgressView() }
            if rows.isEmpty && !busy { Text("暂无群聊") }
            if hasMore { Button("加载更多") { Task { await load(older: true) } }.disabled(busy) }
            if let error { ErrorBanner(message: error) { Task { await load() } } }
        }.puboList().chatNavigationTitle("群聊", embedded: embedded).toolbar { if !embedded { Button("创建群聊") { creating = true } } }
            .task(id: section) { rows = []; hasMore = false; await load() }.refreshable { await load() }
            .sheet(isPresented: $creating, onDismiss: { if section != "owned" { selectedSection = "owned" } else { Task { await load() } } }) { RoomEditor() }
    }
    private func load(older: Bool = false) async {
        let requestedSection = section; busy = true; defer { if requestedSection == section { busy = false } }
        do {
            var fields: [String: JSONValue] = ["limit": .number(30)]
            if older, let id = rows.last?.id { fields["untilId"] = .string(id) }
            let value = try await session.call(endpoint, fields); try Task.checkCancellation()
            guard requestedSection == section, case .array = value else { return }
            let page = Record.list(value); rows = older ? rows + page.filter { p in !rows.contains { $0.id == p.id } } : page; hasMore = page.count == 30; error = nil
        } catch { if !Task.isCancelled && requestedSection == section { self.error = error.localizedDescription } }
    }
}

struct RoomEditor: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    var room: Record?
    @State private var name = ""
    @State private var description = ""
    @State private var loaded = false
    @State private var busy = false
    @State private var pending = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                TextField("群聊名称", text: $name); TextField("群聊说明", text: $description, axis: .vertical)
                if pending { Text("上次创建的结果尚未确认，请先在“我创建的”列表核对，避免重复创建。"); Button("已核对，继续") { do { try session.markPendingAction("room-create", pending: false); pending = false } catch { self.error = error.localizedDescription } } }
                if let error { ErrorBanner(message: error) }
                Button("保存群聊") { Task { await save() } }.disabled(busy || pending || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.puboForm().navigationTitle(room == nil ? "创建群聊" : "修改群聊")
                .toolbar { Button("关闭") { dismiss() }.disabled(busy) }
                .task { if !loaded { loaded = true; name = room?["name"].string ?? ""; description = room?["description"].string ?? ""; pending = room == nil && session.hasPendingAction("room-create") } }
        }.interactiveDismissDisabled(busy)
    }
    private func save() async {
        guard !busy && !pending else { return }
        guard name.unicodeScalars.count <= 256 && description.unicodeScalars.count <= 1024 else { error = "名称最多 256 字，说明最多 1024 字。"; return }
        busy = true; defer { busy = false }
        do {
            var fields: [String: JSONValue] = [:]
            if let room {
                let fresh = Record(try await session.call("chat/rooms/show", ["roomId": .string(room.id)]))
                guard fresh["ownerId"].string == session.user?.id else { throw APIError(code: "PERMISSION_DENIED", message: "群主权限已发生变化。") }
                guard fresh["name"] == room["name"], fresh["description"] == room["description"] else { throw APIError(code: "CONFLICT", message: "群聊资料已变化，请关闭后重新打开。") }
                fields["roomId"] = .string(room.id)
                if name != room["name"].string { fields["name"] = .string(name) }; if description != room["description"].string { fields["description"] = .string(description) }
                _ = try await session.call("chat/rooms/update", fields, mutation: true)
                let check = try await session.call("chat/rooms/show", ["roomId": .string(room.id)])
                guard check["name"].string == name && check["description"].string == description else { throw APIError.uncertain }
            } else {
                try session.markPendingAction("room-create", pending: true); pending = true
                let created = Record(try await session.call("chat/rooms/create", ["name": .string(name), "description": .string(description)], mutation: true))
                guard !created.id.isEmpty else { throw APIError.uncertain }
                try session.markPendingAction("room-create", pending: false); pending = false
            }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct RoomMembersView: View {
    @Environment(AppSession.self) private var session
    let roomID: String
    var canInvite = false
    var embedded = false
    var owner: Record? = nil
    @State private var rows: [Record] = []
    @State private var hasMore = false
    @State private var busy = false
    @State private var error: String?
    @State private var inviting = false
    var body: some View {
        List {
            if let owner, !owner.id.isEmpty { NavigationLink { ProfileView(userID: owner.id) } label: { HStack { Avatar(user: owner); Text(owner.displayName); Text("群主").font(.caption).foregroundStyle(.secondary) } } }
            ForEach(rows.filter { $0["user"]["id"].string != owner?.id }) { row in let user = Record(row["user"]); NavigationLink { ProfileView(userID: user.id) } label: { HStack { Avatar(user: user); Text(user.displayName) } } }
            if hasMore { Button("加载更多成员") { Task { await load(older: true) } }.disabled(busy) }
            if busy { ProgressView() }
            if let error { ErrorBanner(message: error) { Task { await load() } } }
        }.puboList().chatNavigationTitle("群聊成员", embedded: embedded).toolbar { if canInvite { Button("邀请成员") { inviting = true } } }
            .sheet(isPresented: $inviting) { UserPicker { user in Task { await invite(user.id) } } }
            .task { await load() }.refreshable { await load() }
    }
    private func invite(_ id: String) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do { _ = try await session.call("chat/rooms/invitations/create", ["roomId": .string(roomID), "userId": .string(id)], mutation: true); error = "邀请已发送。" }
        catch { self.error = error.localizedDescription }
    }
    private func load(older: Bool = false) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            var fields: [String: JSONValue] = ["roomId": .string(roomID), "limit": .number(30)]
            if older, let id = rows.last?.id { fields["untilId"] = .string(id) }
            let value = try await session.call("chat/rooms/members", fields); try Task.checkCancellation()
            guard case .array = value else { throw APIError.invalidResponse }
            let page = Record.list(value); rows = older ? rows + page.filter { p in !rows.contains { $0.id == p.id } } : page; hasMore = page.count == 30; error = nil
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}
