import SwiftUI
import PUBOCore

struct CollectionsView: View {
    @Environment(AppSession.self) private var session
    let kind: CollectionKind
    @State private var mode = "mine"
    @State private var query = ""
    @State private var rows: [Record] = []
    @State private var busy = false
    @State private var more = false
    @State private var error: String?
    @State private var creating = false
    @State private var revision = 0
    private var context: String { mode + query + String(revision) }
    private var endpoint: String {
        switch kind {
        case .channel: return mode == "search" ? "channels/search" : "channels/" + (mode == "mine" ? "owned" : mode)
        case .gallery: return mode == "mine" ? "users/gallery/posts" : mode == "latest" ? "gallery/posts" : "gallery/" + mode
        default: return kind.base + "/list"
        }
    }
    private var paginated: Bool { !(kind == .list || kind == .antenna || (kind == .channel && ["featured", "my-favorites"].contains(mode)) || (kind == .gallery && mode == "popular")) }
    var body: some View {
        List {
            if kind == .channel || kind == .gallery {
                Picker("分类", selection: $mode) {
                    Text("我的").tag("mine"); Text("推荐").tag("featured")
                    if kind == .channel { Text("关注").tag("followed"); Text("收藏").tag("my-favorites"); Text("搜索").tag("search") }
                    else { Text("最新").tag("latest"); Text("热门").tag("popular") }
                }
            }
            if mode == "search" { TextField("搜索频道", text: $query) }
            ForEach(rows) { row in
                NavigationLink { CollectionDetail(kind: kind, itemID: row.id) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(row[kind.nameKey].string ?? kind.title).font(.headline)
                        if let desc = row["description"].string { Text(desc).font(.caption).lineLimit(2).foregroundStyle(.secondary) }
                    }
                }
            }
            if rows.isEmpty && !busy { Text("暂无内容") }
            if busy { ProgressView() }
            if more { Button("加载更多") { Task { await load(older: true) } }.disabled(busy) }
            if let error { ErrorBanner(message: error) { revision += 1 } }
        }.puboList().navigationTitle(kind.title).toolbar { Button("创建" + kind.title) { creating = true } }
            .task(id: context) { rows = []; more = false; do { if mode == "search" { try await Task.sleep(for: .milliseconds(350)) }; await load() } catch {} }
            .refreshable { revision += 1 }
            .sheet(isPresented: $creating, onDismiss: { revision += 1 }) { CollectionEditor(kind: kind) }
    }
    private func load(older: Bool = false) async {
        let request = context; busy = true; defer { if request == context { busy = false } }
        do {
            var fields: [String: JSONValue] = paginated ? ["limit": .number(30)] : [:]
            if older, let id = rows.last?.id { fields["untilId"] = .string(id) }
            if kind == .gallery && mode == "mine" { fields["userId"] = .string(session.user?.id ?? "") }
            if mode == "search" { fields["query"] = .string(query) }
            let value = try await session.call(endpoint, fields); try Task.checkCancellation(); guard request == context else { return }
            guard case .array = value else { throw APIError.invalidResponse }
            let page = Record.list(value); rows = older ? rows + page.filter { p in !rows.contains { $0.id == p.id } } : page; more = paginated && page.count == 30; error = nil
        } catch { if !Task.isCancelled && request == context { self.error = error.localizedDescription } }
    }
}

struct CollectionDetail: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let kind: CollectionKind
    let itemID: String
    @State private var item: Record?
    @State private var notes: [Record] = []
    @State private var busy = false
    @State private var more = false
    @State private var error: String?
    @State private var editing = false
    @State private var deleting = false
    @State private var composing = false
    private var fields: [String: JSONValue] { [kind.idKey: .string(itemID)] }
    private var mine: Bool { kind == .list || kind == .antenna || (item?["userId"].string ?? item?["user"]["id"].string) == session.user?.id }
    var body: some View {
        List {
            if let item {
                Section {
                    Text(item[kind.nameKey].string ?? "").font(.title2.bold())
                    if let description = item["description"].string { NoteText(text: description) }
                    if kind == .channel {
                        if let url = safeMediaURL(item["bannerUrl"].string) { AsyncImage(url: url) { $0.resizable().scaledToFit() } placeholder: { Color.clear }.frame(maxHeight: 200) }
                        Button(item["isFollowing"].bool ? "取消关注频道" : "关注频道") { Task { await action(item["isFollowing"].bool ? "unfollow" : "follow") } }
                        Button(item["isFavorited"].bool ? "取消收藏频道" : "收藏频道") { Task { await action(item["isFavorited"].bool ? "unfavorite" : "favorite") } }
                        if !item["isArchived"].bool { Button("在此频道发帖") { composing = true } }
                    }
                    if kind == .list { NavigationLink("列表成员") { CollectionMembersView(listID: itemID) } }
                    if kind == .gallery {
                        ForEach(Record.list(item["files"])) { PublicMedia(file: $0, noteID: "", sourceURL: Endpoint.origin.appendingPathComponent("gallery/" + itemID)) }
                        Button(item["isLiked"].bool ? "取消喜欢" : "喜欢") { Task { await action(item["isLiked"].bool ? "unlike" : "like") } }
                    }
                    if kind == .clip { Button(item["isFavorited"].bool ? "取消收藏剪藏" : "收藏剪藏") { Task { await action(item["isFavorited"].bool ? "unfavorite" : "favorite") } } }
                }.disabled(busy)
                ForEach(notes) { note in
                    NoteCard(note: note)
                    if mine && (kind == .clip || kind == .antenna) { Button("从" + kind.title + "移除此帖", role: .destructive) { Task { await removeNote(note.id) } }.disabled(busy) }
                }
            }
            if busy { ProgressView() }
            if more { Button("加载更多帖子") { Task { await load(older: true) } }.disabled(busy) }
            if let error { ErrorBanner(message: error) { Task { await load() } } }
        }.puboList().navigationTitle(kind.title)
            .toolbar { if item != nil && mine { Menu { Button("修改" + kind.title) { editing = true }; if kind != .channel { Button("删除" + kind.title, role: .destructive) { deleting = true } } } label: { Image(systemName: "ellipsis") } } }
            .task { await load() }.refreshable { await load() }
            .sheet(isPresented: $editing, onDismiss: { Task { await load() } }) { CollectionEditor(kind: kind, item: item) }
            .sheet(isPresented: $composing, onDismiss: { Task { await load() } }) { ComposeView(channelID: itemID) {} }
            .confirmationDialog("删除" + kind.title + "后无法恢复，是否继续？", isPresented: $deleting) { Button("确认删除", role: .destructive) { Task { await action("delete") } } }
    }
    private func load(older: Bool = false) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            if !older { item = Record(try await session.call(kind.base + "/show", fields)) }
            if kind != .gallery {
                var request = fields; request["limit"] = .number(30); if older, let id = notes.last?.id { request["untilId"] = .string(id) }
                let value = try await session.call(kind.feed, request); try Task.checkCancellation()
                guard case .array = value else { throw APIError.invalidResponse }; let page = Record.list(value)
                notes = older ? notes + page.filter { p in !notes.contains { $0.id == p.id } } : page; more = page.count == 30
            }
            error = nil
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func action(_ action: String) async {
        guard !busy else { return }; busy = true
        do {
            _ = try await session.call(kind.base + "/" + action, fields, mutation: true)
            if action == "delete" { busy = false; dismiss(); return }
            item = Record(try await session.call(kind.base + "/show", fields)); error = nil
        } catch { self.error = error.localizedDescription }
        busy = false
    }
    private func removeNote(_ id: String) async {
        guard !busy else { return }; busy = true
        do { var fields = self.fields; fields["noteId"] = .string(id); _ = try await session.call(kind.base + "/remove-note", fields, mutation: true); notes.removeAll { $0.id == id }; error = nil }
        catch { self.error = error.localizedDescription }; busy = false
    }
}
