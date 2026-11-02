import SwiftUI
import PUBOCore

struct ContactsView: View {
    @Environment(AppSession.self) private var session
    @State private var groups: [Record] = []
    @State private var name = ""
    @State private var editing: Record?
    @State private var showName = false
    @State private var deleting: Record?
    @State private var error: String?
    @State private var busy = false
    @State private var uncertain = false
    var body: some View {
        List {
            if let user = session.user { NavigationLink("我的关注") { FollowListView(userID: user.id, followers: false) }; NavigationLink("我的关注者") { FollowListView(userID: user.id, followers: true) } }
            ForEach(groups) { group in
                NavigationLink { ContactGroupView(group: group) } label: { HStack { Text(group["name"].string ?? "联系人分组"); Spacer(); Text("\(group["userIds"].array.count)").foregroundStyle(.secondary) } }
                    .swipeActions { Button("重命名") { editing = group; name = group["name"].string ?? ""; showName = true }; Button("删除", role: .destructive) { deleting = group } }
            }
            if let error { ErrorBanner(message: error) }
            if uncertain { Text("请先核对分组列表，确认没有重复创建。").font(.caption); Button("已核对，继续操作") { do { try session.markPendingAction("contact-group-create", pending: false); uncertain = false } catch { self.error = error.localizedDescription } } }
        }.puboList().navigationTitle("联系人").toolbar { Button("新建分组") { editing = nil; name = ""; showName = true }.disabled(busy || uncertain) }
            .task { uncertain = session.hasPendingAction("contact-group-create"); await load() }.refreshable { await load() }
            .alert(editing == nil ? "新建联系人分组" : "重命名分组", isPresented: $showName) {
                TextField("分组名称", text: $name)
                Button("保存") { Task { await save() } }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 100)
                Button("取消", role: .cancel) { }
            }
            .confirmationDialog("删除联系人分组？会话和联系人账号仍会保留。", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                if let deleting { Button("删除分组", role: .destructive) { Task { await remove(deleting) } } }
            }
    }
    private func load() async {
        do { let result = try await session.call("chat/contact-groups/list"); try Task.checkCancellation(); guard case .array = result else { throw APIError.invalidResponse }; groups = Record.list(result) }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func save() async {
        guard !busy, !uncertain else { return }; busy = true; defer { busy = false }
        do {
            if editing == nil { try session.markPendingAction("contact-group-create", pending: true) }
            var fields: [String: JSONValue] = ["name": .string(name.trimmingCharacters(in: .whitespacesAndNewlines))]
            if let editing { fields["groupId"] = .string(editing.id) }
            _ = try await session.call(editing == nil ? "chat/contact-groups/create" : "chat/contact-groups/update", fields, mutation: true)
            try session.markPendingAction("contact-group-create", pending: false); error = nil
        } catch { uncertain = (error as? APIError)?.code == "OUTCOME_UNKNOWN" || session.hasPendingAction("contact-group-create"); self.error = error.localizedDescription }
        await load()
    }
    private func remove(_ group: Record) async {
        guard !busy else { return }; busy = true; defer { busy = false; deleting = nil }
        do { _ = try await session.call("chat/contact-groups/delete", ["groupId": .string(group.id)], mutation: true); error = nil }
        catch { self.error = "请刷新后核对分组是否仍存在。" }
        await load()
    }
}

struct ContactGroupView: View {
    @Environment(AppSession.self) private var session
    let group: Record
    @State private var users: [Record] = []
    @State private var ids: [String] = []
    @State private var offset = 0
    @State private var adding = false
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        List {
            ForEach(users) { user in
                NavigationLink { ChatView(peer: user) } label: { HStack { Avatar(user: user); Text(user.displayName) } }
                    .swipeActions { Button("移出分组", role: .destructive) { Task { await change(user, add: false) } } }
            }
            if offset < ids.count { Button("加载更多联系人") { Task { await page() } }.disabled(busy) }
            if let error { ErrorBanner(message: error) }
        }.puboList().navigationTitle(group["name"].string ?? "联系人分组")
            .toolbar { Button("添加联系人") { adding = true }.disabled(busy) }
            .sheet(isPresented: $adding) { UserPicker { user in Task { await change(user, add: true) } } }
            .task { await reload() }.refreshable { await reload() }
    }
    private func reload() async {
        do {
            let current = Record.list(try await session.call("chat/contact-groups/list")).first { $0.id == group.id }
            guard let current else { ids = []; users = []; throw APIError(code: "GROUP_MISSING", message: "联系人分组已删除。") }
            ids = current["userIds"].array.compactMap(\.string); users = []; offset = 0; await page()
        } catch { self.error = error.localizedDescription }
    }
    private func page() async {
        guard !busy, offset < ids.count else { return }; busy = true; defer { busy = false }
        do {
            let requested = Array(ids.dropFirst(offset).prefix(50))
            let page = Record.list(try await session.call("users/show", ["userIds": .strings(requested)])); try Task.checkCancellation()
            users += page; offset += requested.count; error = page.count == requested.count ? nil : "部分联系人已不可用。"
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func change(_ user: Record, add: Bool) async {
        guard !busy else { return }; busy = true
        do { _ = try await session.call(add ? "chat/contact-groups/add-user" : "chat/contact-groups/remove-user", ["groupId": .string(group.id), "userId": .string(user.id)], mutation: true); error = nil }
        catch { self.error = error.localizedDescription }
        busy = false; await reload()
    }
}
