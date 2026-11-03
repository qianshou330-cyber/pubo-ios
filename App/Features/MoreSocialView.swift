import SwiftUI
import PUBOCore

struct MoreSocialView: View {
    var body: some View {
        List {
            Section("社区") {
                NavigationLink("探索热门") { FeaturedNotesView() }
                ForEach(CollectionKind.allCases) { kind in NavigationLink(kind.title) { CollectionsView(kind: kind) } }
                NavigationLink("联系人") { ContactsView() }
                NavigationLink("群聊") { RoomsView() }
                NavigationLink("网盘") { DriveManagerView() }
            }
            Section("网页版") {
                Text("以下功能在系统浏览器中打开；网页主题、CSS 和插件只影响网页版。").font(.caption)
                Link("Pages · 网页版", destination: Endpoint.origin.appendingPathComponent("pages"))
                Link("Play · 网页版", destination: Endpoint.origin.appendingPathComponent("play"))
                Link("Deck · 网页版", destination: Endpoint.origin.appending(queryItems: [URLQueryItem(name: "ui", value: "deck")]))
                Link("主题 · 网页版", destination: Endpoint.origin.appendingPathComponent("settings/theme"))
                Link("插件 · 网页版", destination: Endpoint.origin.appendingPathComponent("settings/plugin"))
                Link("网页脚本工具 · 网页版", destination: Endpoint.origin.appendingPathComponent("scratchpad"))
                Link("网页界面偏好 · 网页版", destination: Endpoint.origin.appendingPathComponent("settings/preferences"))
                Link("网页导航与状态栏 · 网页版", destination: Endpoint.origin.appendingPathComponent("settings/navbar"))
                Link("网页状态栏 · 网页版", destination: Endpoint.origin.appendingPathComponent("settings/statusbar"))
                Link("网页声音 · 网页版", destination: Endpoint.origin.appendingPathComponent("settings/sounds"))
                Link("网页表情面板 · 网页版", destination: Endpoint.origin.appendingPathComponent("settings/emoji-palette"))
                Link("Deck 设置 · 网页版", destination: Endpoint.origin.appendingPathComponent("settings/deck"))
                Link("网页 CSS · 网页版", destination: Endpoint.origin.appendingPathComponent("settings/custom-css"))
                Link("网页偏好配置文件 · 网页版", destination: Endpoint.origin.appendingPathComponent("settings/profiles"))
                Text("游戏 · 服务器当前关闭").foregroundStyle(.secondary)
            }
        }.puboList().navigationTitle("更多功能")
    }
}

struct FeaturedNotesView: View {
    @Environment(AppSession.self) private var session
    @State private var rows: [Record] = []
    @State private var busy = false
    @State private var more = false
    @State private var error: String?
    var body: some View {
        List {
            ForEach(rows) { NoteCard(note: $0) }
            if more { Button("加载更多") { Task { await load(older: true) } }.disabled(busy) }
            if busy { ProgressView() }
            if let error { ErrorBanner(message: error) { Task { await load() } } }
        }.puboList().navigationTitle("探索热门").task { await load() }.refreshable { await load() }
    }
    private func load(older: Bool = false) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            var fields: [String: JSONValue] = ["limit": .number(30)]; if older, let id = rows.last?.id { fields["untilId"] = .string(id) }
            let result = try await session.call("notes/featured", fields); try Task.checkCancellation()
            guard case .array = result else { throw APIError.invalidResponse }; let page = Record.list(result)
            rows = older ? rows + page.filter { p in !rows.contains { $0.id == p.id } } : page; more = page.count == 30; error = nil
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

struct ClipPicker: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let noteID: String
    @State private var rows: [Record] = []
    @State private var more = false
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                ForEach(rows) { row in Button(row["name"].string ?? "剪藏") { Task { await add(row.id) } }.disabled(busy) }
                if more { Button("加载更多剪藏") { Task { await load() } }.disabled(busy) }
                if let error { ErrorBanner(message: error) }
                if rows.isEmpty && !busy { Text("请先在“更多功能 → 剪藏”中创建剪藏。") }
            }.puboList().navigationTitle("加入剪藏").toolbar { Button("关闭") { dismiss() }.disabled(busy) }.task { await load() }
        }
    }
    private func load() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do { var fields: [String: JSONValue] = ["limit": .number(30)]; if let id = rows.last?.id { fields["untilId"] = .string(id) }; let page = Record.list(try await session.call("clips/list", fields)); rows += page.filter { p in !rows.contains { $0.id == p.id } }; more = page.count == 30; error = nil }
        catch { self.error = error.localizedDescription }
    }
    private func add(_ id: String) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do { _ = try await session.call("clips/add-note", ["clipId": .string(id), "noteId": .string(noteID)], mutation: true); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

struct ReactionDetailsView: View {
    @Environment(AppSession.self) private var session
    let noteID: String
    @State private var rows: [Record] = []
    @State private var more = false
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        List {
            ForEach(rows) { row in let user = Record(row["user"]); NavigationLink { ProfileView(userID: user.id) } label: { HStack { Avatar(user: user); Text(user.displayName); Spacer(); NoteText(text: row["type"].string ?? "", expands: false) } } }
            if more { Button("加载更多反应") { Task { await load() } }.disabled(busy) }
            if busy { ProgressView() }; if let error { ErrorBanner(message: error) }
        }.puboList().navigationTitle("反应详情").task { await load() }
    }
    private func load() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do { var fields: [String: JSONValue] = ["noteId": .string(noteID), "limit": .number(30)]; if let id = rows.last?.id { fields["untilId"] = .string(id) }; let page = Record.list(try await session.call("notes/reactions", fields)); try Task.checkCancellation(); rows += page.filter { p in !rows.contains { $0.id == p.id } }; more = page.count == 30; error = nil }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}
