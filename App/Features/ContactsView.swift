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
    @State private var loading = false
    @State private var loaded = false
    @State private var visible = false
    @State private var readID = UUID()
    @State private var writeID = UUID()
    @State private var initializedGeneration: UUID?
    var body: some View {
        List {
            if let user = session.user { NavigationLink("我的关注") { FollowListView(userID: user.id, followers: false) }; NavigationLink("我的关注者") { FollowListView(userID: user.id, followers: true) } }
            if loading { ProgressView().accessibilityIdentifier("contacts.loading") }
            if loaded && groups.isEmpty && error == nil { Text("暂无联系人分组").foregroundStyle(.secondary) }
            ForEach(groups) { group in
                NavigationLink { ContactGroupView(group: group) } label: { HStack { Text(group["name"].string ?? "联系人分组"); Spacer(); Text("\(group["userIds"].array.count)").foregroundStyle(.secondary) } }
                    .swipeActions { Button("重命名") { editing = group; name = group["name"].string ?? ""; showName = true }; Button("删除", role: .destructive) { deleting = group } }.disabled(busy)
            }
            if let error { ErrorBanner(message: error, retryIdentifier: "contacts.retry") { Task { await load() } } }
            if uncertain { Text("请先核对分组列表，确认没有重复创建。").font(.caption); Button("已核对，继续操作") { do { try session.markPendingAction("contact-group-create", pending: false); uncertain = false } catch { self.error = error.localizedDescription } } }
        }.puboList().navigationTitle("联系人").toolbar { Button("新建分组") { editing = nil; name = ""; showName = true }.disabled(busy || uncertain) }
            .task(id: session.generation) {
                visible = true; readID = UUID(); loading = false
                if initializedGeneration != session.generation {
                    initializedGeneration = session.generation; writeID = UUID(); busy = false
                }
                groups = []; loaded = false; error = nil; showName = false; deleting = nil
                uncertain = session.hasPendingAction("contact-group-create"); await load()
            }.refreshable { await load() }
            .onDisappear { visible = false; readID = UUID(); loading = false; showName = false; deleting = nil }
            .alert(editing == nil ? "新建联系人分组" : "重命名分组", isPresented: $showName) {
                TextField("分组名称", text: $name)
                Button("保存") { let generation = session.generation; Task { await save(expectedGeneration: generation) } }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 100)
                Button("取消", role: .cancel) { }
            }
            .confirmationDialog("删除联系人分组？会话和联系人账号仍会保留。", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                if let deleting { Button("删除分组", role: .destructive) { let generation = session.generation; Task { await remove(deleting, expectedGeneration: generation) } } }
            }
    }
    private func load() async {
        guard visible, !busy else { return }
        let ticket = UUID(), generation = session.generation
        readID = ticket; loading = true
        defer { if readID == ticket { loading = false } }
        do {
            let result = try await session.call("chat/contact-groups/list")
            try Task.checkCancellation()
            guard visible, readID == ticket, generation == session.generation else { return }
            guard case .array = result else { throw APIError.invalidResponse }
            let next = Record.list(result)
            guard next.count == result.array.count, next.allSatisfy({ !$0.id.isEmpty }), Set(next.map(\.id)).count == next.count else { throw APIError.invalidResponse }
            groups = next; loaded = true; error = nil
        } catch {
            guard !Task.isCancelled, visible, readID == ticket, generation == session.generation else { return }
            self.error = error.localizedDescription
        }
    }
    private func save(expectedGeneration: UUID) async {
        guard expectedGeneration == session.generation, visible, !busy, !uncertain else { return }
        let generation = session.generation, ticket = UUID(), target = editing
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 100 else { return }
        busy = true; writeID = ticket; readID = UUID(); loading = false
        var failure: String?
        do {
            if target == nil { try session.markPendingAction("contact-group-create", pending: true) }
            var fields: [String: JSONValue] = ["name": .string(title)]
            if let target { fields["groupId"] = .string(target.id) }
            _ = try await session.call(target == nil ? "chat/contact-groups/create" : "chat/contact-groups/update", fields, mutation: true)
            guard writeID == ticket, generation == session.generation else { return }
            if target == nil { try session.markPendingAction("contact-group-create", pending: false); uncertain = false }
            error = nil
        } catch {
            guard writeID == ticket, generation == session.generation else { return }
            uncertain = (error as? APIError)?.code == "OUTCOME_UNKNOWN" || session.hasPendingAction("contact-group-create")
            failure = error.localizedDescription
        }
        guard writeID == ticket, generation == session.generation else { return }
        busy = false
        await load()
        if visible, writeID == ticket, generation == session.generation, let failure { error = failure }
    }
    private func remove(_ group: Record, expectedGeneration: UUID) async {
        guard expectedGeneration == session.generation, visible, !busy else { return }
        let generation = session.generation, ticket = UUID()
        busy = true; writeID = ticket; readID = UUID(); loading = false
        var failure: String?
        do { _ = try await session.call("chat/contact-groups/delete", ["groupId": .string(group.id)], mutation: true) }
        catch { failure = "请刷新后核对分组是否仍存在。" }
        guard writeID == ticket, generation == session.generation else { return }
        busy = false; deleting = nil; error = nil
        await load()
        if visible, writeID == ticket, generation == session.generation, let failure { error = failure }
    }
}

struct ContactGroupView: View {
    @Environment(AppSession.self) private var session
    let group: Record
    @State private var members = ContactMemberPage()
    @State private var adding = false
    @State private var loading = false
    @State private var changing = false
    @State private var loaded = false
    @State private var visible = false
    @State private var missing = false
    @State private var retryReset = true
    @State private var error: String?
    @State private var warning: String?
    @State private var readID = UUID()
    @State private var writeID = UUID()
    @State private var initializedGeneration: UUID?
    var body: some View {
        List {
            if loading { ProgressView().accessibilityIdentifier("contactGroup.loading") }
            ForEach(members.rows) { user in
                NavigationLink { ChatView(peer: user) } label: { HStack { Avatar(user: user); Text(user.displayName) } }
                    .swipeActions { Button("移出分组", role: .destructive) { let generation = session.generation; Task { await change(user, add: false, expectedGeneration: generation) } }.disabled(changing) }
            }
            if loaded && members.rows.isEmpty && error == nil { Text("分组暂无联系人").foregroundStyle(.secondary) }
            if members.hasMore { Button("加载更多联系人") { Task { await load(reset: false) } }.disabled(loading || changing).accessibilityIdentifier("contactGroup.more") }
            if let warning { Text(warning).font(.caption).foregroundStyle(.secondary) }
            if let error { ErrorBanner(message: error, retryIdentifier: "contactGroup.retry") { Task { await load(reset: retryReset) } } }
        }.puboList().navigationTitle(group["name"].string ?? "联系人分组")
            .toolbar {
                // Remains available during the initial read, including an otherwise empty List.
                Button { Task { await load(reset: true) } } label: { Label("刷新联系人", systemImage: "arrow.clockwise") }
                    .disabled(changing).accessibilityIdentifier("contactGroup.refresh")
                Button("添加联系人") { adding = true }.disabled(changing || loading || missing || !loaded)
            }
            .sheet(isPresented: $adding) { UserPicker { user in let generation = session.generation; Task { await change(user, add: true, expectedGeneration: generation) } } }
            .task(id: session.generation.uuidString + group.id) {
                visible = true; readID = UUID(); loading = false
                if initializedGeneration != session.generation {
                    initializedGeneration = session.generation; writeID = UUID(); changing = false
                }
                adding = false; members = ContactMemberPage(); loaded = false; missing = false; error = nil; warning = nil
                await load(reset: true)
            }.refreshable { await load(reset: true) }
            .onDisappear { visible = false; readID = UUID(); loading = false; adding = false }
    }
    private func load(reset: Bool) async {
        guard visible, !changing, reset || (!loading && members.hasMore) else { return }
        let ticket = UUID(), generation = session.generation
        readID = ticket; loading = true
        defer { if readID == ticket { loading = false } }
        do {
            // Build refresh off-screen: a failed refresh keeps the last valid rows and cursor.
            var next = members
            if reset {
                let result = try await session.call("chat/contact-groups/list")
                try Task.checkCancellation()
                guard visible, readID == ticket, generation == session.generation else { return }
                guard case .array = result else { throw APIError.invalidResponse }
                let groups = Record.list(result)
                guard groups.count == result.array.count, groups.allSatisfy({ !$0.id.isEmpty }), Set(groups.map(\.id)).count == groups.count else { throw APIError.invalidResponse }
                guard let current = groups.first(where: { $0.id == group.id }) else {
                    members = ContactMemberPage(); missing = true; loaded = true; warning = nil
                    throw APIError(code: "GROUP_MISSING", message: "联系人分组已删除。")
                }
                guard case .array(let rawIDs) = current["userIds"], rawIDs.allSatisfy({ $0.string != nil }) else { throw APIError.invalidResponse }
                next = ContactMemberPage(ids: rawIDs.compactMap(\.string))
            }
            let requested = next.nextIDs
            var complete = true
            if !requested.isEmpty {
                let result = try await session.call("users/show", ["userIds": .strings(requested)])
                try Task.checkCancellation()
                guard visible, readID == ticket, generation == session.generation else { return }
                complete = try next.apply(result, requested: requested)
            }
            guard visible, readID == ticket, generation == session.generation else { return }
            members = next; missing = false; loaded = true; error = nil
            if reset { warning = nil }
            if !complete { warning = "部分联系人已不可用。" }
        } catch {
            guard !Task.isCancelled, visible, readID == ticket, generation == session.generation else { return }
            retryReset = reset; self.error = error.localizedDescription
        }
    }
    private func change(_ user: Record, add: Bool, expectedGeneration: UUID) async {
        guard expectedGeneration == session.generation, visible, !changing, !missing else { return }
        let ticket = UUID(), generation = session.generation
        writeID = ticket; changing = true; readID = UUID(); loading = false; adding = false
        var failure: String?
        do { _ = try await session.call(add ? "chat/contact-groups/add-user" : "chat/contact-groups/remove-user", ["groupId": .string(group.id), "userId": .string(user.id)], mutation: true) }
        catch { failure = error.localizedDescription }
        guard writeID == ticket, generation == session.generation else { return }
        changing = false; await load(reset: true)
        if visible, writeID == ticket, generation == session.generation, let failure { error = failure; retryReset = true }
    }
}
