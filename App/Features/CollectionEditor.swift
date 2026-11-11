import SwiftUI
import PUBOCore

struct CollectionEditor: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let kind: CollectionKind
    var item: Record?
    @State private var values: [String: JSONValue] = [:]
    @State private var baseline: [String: JSONValue] = [:]
    @State private var lists: [Record] = []
    @State private var fileNames: [String: String] = [:]
    @State private var keywordText = ""
    @State private var excludeText = ""
    @State private var usersText = ""
    @State private var pinnedText = ""
    @State private var choosing = false
    @State private var loaded = false
    @State private var busy = false
    @State private var pending = false
    @State private var error: String?
    private var canSave: Bool { ChannelPolicy.canSave(kind: kind, creating: item == nil, user: session.user?.raw ?? .null) }
    private var pendingKey: String { "collection-create-" + kind.rawValue }
    private func string(_ key: String) -> Binding<String> { Binding(get: { values[key]?.string ?? "" }, set: { values[key] = .string($0) }) }
    private func flag(_ key: String) -> Binding<Bool> { Binding(get: { values[key]?.bool ?? false }, set: { values[key] = .bool($0) }) }
    private var nameLimit: Int { kind == .channel ? 128 : kind == .gallery ? 1000 : 100 }
    private var galleryFiles: [String] { values["fileIds"]?.array.compactMap(\.string) ?? [] }
    private var fields: some View {
        Group {
            TextField(kind == .gallery ? "标题" : "名称", text: string(kind.nameKey))
            if kind == .channel || kind == .clip || kind == .gallery { TextField("说明", text: string("description"), axis: .vertical).lineLimit(3...8) }
            if kind == .clip || (kind == .list && item != nil) { Toggle("公开", isOn: flag("isPublic")) }
            if kind == .channel {
                TextField("频道颜色（如 #86b300）", text: string("color"))
                Toggle("敏感频道", isOn: flag("isSensitive")); Toggle("允许转发到频道外", isOn: flag("allowRenoteToExternal"))
                if item != nil { Toggle("已归档", isOn: flag("isArchived")); TextField("置顶帖子 ID，每行一个", text: $pinnedText, axis: .vertical) }
                Button("选择封面") { choosing = true }
                if values["bannerId"]?.string != nil { Text(fileNames[values["bannerId"]?.string ?? ""] ?? "已选择封面"); Button("移除封面") { values["bannerId"] = .null } }
            }
            if kind == .gallery {
                Toggle("敏感内容", isOn: flag("isSensitive"))
                ForEach(galleryFiles, id: \.self) { id in HStack { Text(fileNames[id] ?? "媒体文件"); Button("移除") { values["fileIds"] = .strings(galleryFiles.filter { $0 != id }) } } }
                Button("从网盘添加媒体") { choosing = true }.disabled(galleryFiles.count >= 32)
            }
        }
    }
    private var antennaFields: some View {
        Section("接收条件") {
            Picker("来源", selection: string("src")) { Text("首页").tag("home"); Text("所有帖子").tag("all"); Text("指定用户").tag("users"); Text("排除指定用户").tag("users_blacklist"); Text("列表").tag("list") }
            if values["src"]?.string == "list" { Picker("列表", selection: string("userListId")) { Text("请选择列表").tag(""); ForEach(lists) { Text($0["name"].string ?? "列表").tag($0.id) } } }
            if ["users", "users_blacklist"].contains(values["src"]?.string ?? "") { TextField("用户名，每行一个", text: $usersText, axis: .vertical).textInputAutocapitalization(.never) }
            TextField("关键词", text: $keywordText, axis: .vertical); TextField("排除关键词", text: $excludeText, axis: .vertical)
            Text("同一行用空格分隔的词必须同时匹配；不同行满足任意一行即可。").font(.caption)
            Toggle("区分大小写", isOn: flag("caseSensitive")); Toggle("仅本站", isOn: flag("localOnly")); Toggle("排除 Bot", isOn: flag("excludeBots")); Toggle("包含回复", isOn: flag("withReplies")); Toggle("仅含附件", isOn: flag("withFile")); Toggle("排除敏感频道", isOn: flag("excludeNotesInSensitiveChannel"))
        }
    }
    var body: some View {
        NavigationStack {
            Form {
                fields.disabled(busy || pending)
                if kind == .antenna { antennaFields.disabled(busy || pending) }
                if pending { Text("上次创建的结果待确认。请先关闭并检查列表，避免重复创建。"); Button("已核对列表，继续创建") { do { try session.markPendingAction(pendingKey, pending: false); pending = false } catch { self.error = error.localizedDescription } } }
                if !canSave { Text("当前账号没有创建频道的权限。").foregroundStyle(.secondary).accessibilityIdentifier("channels.create.unavailable") }
                if let error { ErrorBanner(message: error) }
                Button("保存") { Task { await save() } }.disabled(!loaded || busy || pending || !canSave)
            }.puboForm().navigationTitle((item == nil ? "创建" : "修改") + kind.title)
                .toolbar { Button("关闭") { dismiss() }.disabled(busy) }
                .task { await restore() }
                .sheet(isPresented: $choosing) { DrivePicker { file in
                    fileNames[file.id] = file["name"].string ?? "媒体文件"
                    if kind == .channel { values["bannerId"] = .string(file.id) }
                    else if !galleryFiles.contains(file.id) && galleryFiles.count < 32 { values["fileIds"] = .strings(galleryFiles + [file.id]) }
                } }
        }.interactiveDismissDisabled(busy)
    }
    private func restore() async {
        guard !loaded else { return }
        if let item { values = item.raw.object }
        else {
            values = [kind.nameKey: .string("")]
            if kind == .antenna { values.merge(["src": .string("all"), "keywords": .array([]), "excludeKeywords": .array([]), "users": .array([]), "caseSensitive": .bool(false), "withReplies": .bool(false), "withFile": .bool(false)], uniquingKeysWith: { _, new in new }) }
            if kind == .channel { values["color"] = .string("#86b300"); values["allowRenoteToExternal"] = .bool(true) }
        }
        keywordText = CollectionFields.keywordText(values["keywords"] ?? .null); excludeText = CollectionFields.keywordText(values["excludeKeywords"] ?? .null)
        usersText = values["users"]?.array.compactMap(\.string).joined(separator: "\n") ?? ""
        pinnedText = values["pinnedNoteIds"]?.array.compactMap(\.string).joined(separator: "\n") ?? ""
        for file in Record.list(values["files"] ?? .null) { fileNames[file.id] = file["name"].string }
        baseline = values; pending = item == nil && session.hasPendingAction(pendingKey); loaded = true
        if kind == .antenna { do { lists = Record.list(try await session.call("users/lists/list")) } catch { self.error = error.localizedDescription } }
    }
    private func save() async {
        guard loaded && !busy && !pending else { return }
        guard canSave else { error = "当前账号没有创建频道的权限。"; return }
        let name = values[kind.nameKey]?.string ?? ""
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.unicodeScalars.count <= nameLimit else { error = "请填写有效名称，最多 \(nameLimit) 字。"; return }
        guard (values["description"]?.string ?? "").unicodeScalars.count <= 2048 else { error = "说明最多 2048 字。"; return }
        var allowed = [kind.nameKey]
        switch kind {
        case .channel:
            allowed += ["description", "bannerId", "color", "isSensitive", "allowRenoteToExternal"]
            if item != nil { allowed += ["isArchived", "pinnedNoteIds"]; values["pinnedNoteIds"] = .strings(pinnedText.split(whereSeparator: \.isWhitespace).map(String.init)) }
        case .clip: allowed += ["description", "isPublic"]
        case .list: if item != nil { allowed += ["isPublic"] }
        case .gallery: allowed += ["description", "fileIds", "isSensitive"]; guard !galleryFiles.isEmpty else { error = "至少添加一个媒体文件。"; return }
        case .antenna:
            allowed += ["src", "userListId", "keywords", "excludeKeywords", "users", "caseSensitive", "localOnly", "excludeBots", "withReplies", "withFile", "excludeNotesInSensitiveChannel"]
            values["keywords"] = CollectionFields.keywords(keywordText); values["excludeKeywords"] = CollectionFields.keywords(excludeText); values["users"] = .strings(usersText.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
            if values["src"]?.string == "list" { guard let listID = values["userListId"]?.string, !listID.isEmpty else { error = "请选择来源列表。"; return } }
            else { values["userListId"] = .null }
        }
        var request = values.filter { allowed.contains($0.key) }
        busy = true; defer { busy = false }
        do {
            if let item {
                request = CollectionFields.changes(request, from: baseline)
                if request.isEmpty { dismiss(); return }
                let fresh = try await session.call(kind.base + "/show", [kind.idKey: .string(item.id)])
                guard request.keys.allSatisfy({ fresh[$0] == (baseline[$0] ?? .null) }) else { throw APIError(code: "CONFLICT", message: "内容已被更新，请关闭后重新打开核对。") }
                request = CollectionFields.update(request, kind: kind, latest: fresh)
                let wanted = request; request[kind.idKey] = .string(item.id)
                do { _ = try await session.call(kind.base + "/update", request, mutation: true) }
                catch { if (error as? APIError)?.code != "OUTCOME_UNKNOWN" { throw error } }
                let checked = try await session.call(kind.base + "/show", [kind.idKey: .string(item.id)])
                guard wanted.allSatisfy({ checked[$0.key] == $0.value }) else { throw APIError.uncertain }
            } else {
                guard canSave else { throw APIError(code: "CHANNEL_CREATE_UNAVAILABLE", message: "当前账号没有创建频道的权限。") }
                try session.markPendingAction(pendingKey, pending: true); pending = true
                let result = Record(try await session.call(kind.base + "/create", request, mutation: true)); guard !result.id.isEmpty else { throw APIError.uncertain }
                try session.markPendingAction(pendingKey, pending: false); pending = false
            }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct CollectionMembersView: View {
    @Environment(AppSession.self) private var session
    let listID: String
    @State private var rows: [Record] = []
    @State private var busy = false
    @State private var more = false
    @State private var adding = false
    @State private var error: String?
    var body: some View {
        List {
            ForEach(rows) { row in
                let user = Record(row["user"])
                VStack(alignment: .leading) {
                    NavigationLink { ProfileView(userID: user.id) } label: { HStack { Avatar(user: user); Text(user.displayName) } }
                    Button(row["withReplies"].bool ? "不接收此用户的回复" : "接收此用户的回复") { Task { await change("update-membership", user.id, withReplies: !row["withReplies"].bool) } }
                }.swipeActions { Button("移出列表", role: .destructive) { Task { await change("pull", user.id) } } }
            }
            if more { Button("加载更多成员") { Task { await load(older: true) } }.disabled(busy) }
            if busy { ProgressView() }; if let error { ErrorBanner(message: error) }
        }.puboList().navigationTitle("列表成员").toolbar { Button("添加成员") { adding = true }.disabled(busy) }
            .sheet(isPresented: $adding) { UserPicker { user in Task { await change("push", user.id) } } }
            .task { await load() }.refreshable { await load() }
    }
    private func load(older: Bool = false) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            var fields: [String: JSONValue] = ["listId": .string(listID), "limit": .number(30)]; if older, let id = rows.last?.id { fields["untilId"] = .string(id) }
            let page = Record.list(try await session.call("users/lists/get-memberships", fields)); try Task.checkCancellation()
            rows = older ? rows + page.filter { p in !rows.contains { $0.id == p.id } } : page; more = page.count == 30; error = nil
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func change(_ operation: String, _ userID: String, withReplies: Bool? = nil) async {
        guard !busy else { return }; busy = true
        do { var fields: [String: JSONValue] = ["listId": .string(listID), "userId": .string(userID)]; if let withReplies { fields["withReplies"] = .bool(withReplies) }; _ = try await session.call("users/lists/" + operation, fields, mutation: true); error = nil }
        catch { self.error = error.localizedDescription }; busy = false; await load()
    }
}
