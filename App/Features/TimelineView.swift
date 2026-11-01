import SwiftUI
import PUBOCore

struct TimelineCache: Codable {
    let savedAt: Date
    let notes: [Record]
}

struct TimelineView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var timeline = "home"
    @State private var notes: [Record] = []
    @State private var error: String?
    @State private var loading = false
    @State private var hasMore = true
    @State private var composer = false
    @State private var requestID = UUID()
    @State private var requestTimeline = ""
    @State private var cached = false
    @State private var homeRefresh = 0
    @State private var restoredSelection = false
    @State private var firstLoadFinished = false
    @State private var homePath: [HomeDestination] = []
    private var choices: [String] { HomeContent.timelines(user: session.user?.raw ?? .null) }
    private var active: Bool { session.selectedTab == 0 && scenePhase == .active }

    var body: some View {
        NavigationStack(path: $homePath) {
            List {
                HomeAnnouncements(refreshID: homeRefresh) { homePath.append($0) }
                HomeChartPanel(refreshID: homeRefresh) { homePath.append($0) }
                if cached { Text("显示本机缓存，正在获取最新内容").font(.caption).foregroundStyle(.secondary) }
                if let error { ErrorBanner(message: error) { Task { await load() } } }
                if notes.isEmpty && !firstLoadFinished && error == nil {
                    ForEach(0..<3) { _ in PostLoadingSkeleton().puboListRow() }
                }
                ForEach(notes) { note in NoteCard(note: note) }
                if loading && !notes.isEmpty { ProgressView().frame(maxWidth: .infinity) }
                if notes.isEmpty && firstLoadFinished && !loading && error == nil { Text("暂时没有帖子").foregroundStyle(.secondary) }
                if hasMore && !notes.isEmpty { Button("加载更早的帖子") { Task { await load(older: true) } }.disabled(loading) }
                Color.clear.frame(height: 56).listRowSeparator(.hidden).listRowBackground(Color.clear)
            }.puboList().toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: HomeDestination.self) { $0.view }
                .safeAreaInset(edge: .top, spacing: 0) { header }
                .overlay(alignment: .bottomTrailing) {
                    Button { composer = true } label: { Image(systemName: "pencil").font(.title3.bold()).foregroundStyle(.black).frame(width: 52, height: 52).background(.white, in: Circle()).overlay(Circle().strokeBorder(PUBOTheme.divider, lineWidth: 1)).shadow(color: .black.opacity(0.15), radius: 4, y: 2) }
                        .buttonStyle(.plain).padding(16).accessibilityLabel("发帖").accessibilityIdentifier("home.compose")
                }
                .sheet(isPresented: $composer) { ComposeView { Task { await load() } }.environment(\.dynamicTypeSize, typeSize) }
                .refreshable { homeRefresh += 1; await load() }
                .task(id: timeline) {
                    if !restoredSelection {
                        restoredSelection = true
                        if let owner = session.user?.id, let saved = try? session.store?.read(String.self, account: owner, key: "selected-timeline"), choices.contains(saved), saved != timeline { timeline = saved; return }
                    }
                    guard choices.contains(timeline) else { timeline = "home"; return }
                    if let owner = session.user?.id { try? session.store?.save(timeline, account: owner, key: "selected-timeline") }
                    session.stream.showTimeline(timeline)
                    notes = []; hasMore = true; cached = false; firstLoadFinished = false; error = nil
                    if let owner = session.user?.id, let saved = try? session.store?.read(TimelineCache.self, account: "public-" + owner, key: "timeline-" + timeline), !saved.notes.isEmpty, Date().timeIntervalSince(saved.savedAt) < 86_400 { notes = saved.notes; cached = true }
                    await load()
                }
                .onAppear { session.stream.showTimeline(timeline) }
                .onDisappear { session.stream.showTimeline(nil) }
                .onChange(of: choices) { _, available in if !available.contains(timeline) { timeline = "home" } }
                .task(id: session.streamRevision) {
                    guard active else { return }
                    try? await Task.sleep(for: .milliseconds(700))
                    if !Task.isCancelled { await load() }
                }
                .task(id: active) {
                    guard active, restoredSelection else { return }
                    await load()
                }
        }
    }
    private var header: some View {
        HStack(spacing: 0) {
            PUBOTimelineSelector(selection: $timeline, available: choices, compact: true)
            Menu {
                Link("在网页查看时间线", destination: Endpoint.origin)
                Link("隐私政策", destination: Endpoint.origin.appendingPathComponent("privacy.html"))
                Link("支持与反馈", destination: URL(string: "mailto:qianshou330@gmail.com")!)
            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle()) }
                .accessibilityLabel("首页更多").accessibilityIdentifier("home.more")
        }.background(PUBOTheme.background).overlay(alignment: .bottom) { Rectangle().fill(PUBOTheme.divider).frame(height: 1) }
    }
    private func load(older: Bool = false) async {
        guard !loading || requestTimeline != timeline else { return }
        let attempt = UUID(); requestID = attempt; requestTimeline = timeline
        loading = true; defer { if requestID == attempt { loading = false } }
        let selected = timeline
        var fields: [String: JSONValue] = ["limit": .number(20)]
        if older, let id = notes.last?.id { fields["untilId"] = .string(id) }
        do {
            let result = Record.list(try await session.call("notes/\(selected)-timeline", fields))
            try Task.checkCancellation()
            guard selected == timeline, requestID == attempt else { return }
            notes = Records.merge(notes, result, limit: 2_000); error = nil; cached = false; firstLoadFinished = true
            if let owner = session.user?.id { try? session.store?.save(TimelineCache(savedAt: Date(), notes: Array(notes.filter { $0["visibility"].string == "public" }.prefix(100))), account: "public-" + owner, key: "timeline-" + selected) }
            if older || notes.count <= 20 { hasMore = result.count == 20 && notes.count < 2_000 }
        } catch is CancellationError { } catch { if !Task.isCancelled && requestID == attempt { firstLoadFinished = true; self.error = error.localizedDescription } }
    }
}

struct NoteCard: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dynamicTypeSize) private var typeSize
    let note: Record
    var detail = false
    @State private var revealCW = false
    @State private var reactionPicker = false
    @State private var replying = false
    @State private var quoting = false
    @State private var error: String?
    @State private var current: Record?
    @State private var busy = false
    private var shown: Record { let n = current ?? note; return n.text.isEmpty && !n["renote"].isNull ? Record(n["renote"]) : n }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            NavigationLink { ProfileView(userID: shown.user.id) } label: {
                HStack(alignment: .top, spacing: 8) {
                    Avatar(user: shown.user, size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) { Text(shown.user.displayName).font(.subheadline.bold()); if shown.user["isBot"].bool { Text("bot").font(.caption2).padding(.horizontal, 3).overlay(RoundedRectangle(cornerRadius: 3).stroke(PUBOTheme.divider)) } }
                        Text("@" + (shown.user["username"].string ?? "") + (shown.user["host"].string.map { "@" + $0 } ?? "")).font(.caption2).foregroundStyle(PUBOTheme.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if let date = puboDate(shown["createdAt"].string) { Text(date, style: .relative).font(.caption2).foregroundStyle(PUBOTheme.secondary).lineLimit(1) }
                    Image(systemName: shown["visibility"].string == "followers" ? "lock" : shown["visibility"].string == "specified" ? "envelope" : "globe").font(.caption2).foregroundStyle(PUBOTheme.secondary)
                }
            }.buttonStyle(.plain)
            if let cw = shown["cw"].string {
                Button { revealCW.toggle() } label: { Label(cw.isEmpty ? "内容警告 · 点击展开" : cw, systemImage: revealCW ? "eye.slash" : "eye").frame(minHeight: 44) }
                    .buttonStyle(.borderless).accessibilityValue(revealCW ? "已展开" : "已隐藏")
            }
            if shown["cw"].isNull || revealCW {
                if detail { NoteText(text: shown.text, remoteEmojis: shown["emojis"]) }
                else { NavigationLink { NoteDetailView(noteID: shown.id) } label: { NoteText(text: shown.text, remoteEmojis: shown["emojis"]).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityHint("打开帖子详情") }
                ForEach(Record.list(shown["files"])) { file in PublicMedia(file: file) }
                if !shown["poll"].isNull || shown.text.contains("$[") { Link("在网页查看完整内容", destination: Endpoint.origin.appendingPathComponent("notes/" + shown.id)).font(.caption) }
            }
            HStack(spacing: 12) {
                Button { replying = true } label: { HStack(spacing: 4) { Image(systemName: "arrowshape.turn.up.left"); if shown["repliesCount"].int > 0 { Text("\(shown["repliesCount"].int)").font(.caption) } }.frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("回复")
                Menu {
                    Button("转发") { Task { await renote() } }
                    Button("引用转发") { quoting = true }
                } label: { Image(systemName: "arrow.2.squarepath").frame(minWidth: 44, minHeight: 44) }
                Button { reactionPicker = true } label: { Image(systemName: "face.smiling").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("添加表情反应")
                if !shown["myReaction"].isNull { Button("取消反应") { Task { await react(nil) } }.font(.caption) }
            }.buttonStyle(.borderless).foregroundStyle(PUBOTheme.secondary).disabled(busy)
            if !shown["reactions"].object.isEmpty {
                ScrollView(.horizontal) { HStack(spacing: 8) { ForEach(shown["reactions"].object.keys.sorted(), id: \.self) { reaction in Text("\(reaction) \(shown["reactions"][reaction].int)").font(.caption).padding(.horizontal, 10).padding(.vertical, 6).background(PUBOTheme.button, in: Capsule()) } } }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }.buttonStyle(.borderless).font(.subheadline).puboCard(padding: 12).puboListRow()
            .contextMenu { Link("在本站网页打开原帖", destination: Endpoint.origin.appendingPathComponent("notes/" + shown.id)) }
            .sheet(isPresented: $reactionPicker) { ReactionPicker { reaction in Task { await react(reaction) } } }
            .sheet(isPresented: $replying) { ComposeView(replyTo: shown) { }.environment(\.dynamicTypeSize, typeSize) }
            .sheet(isPresented: $quoting) { ComposeView(renote: shown) { }.environment(\.dynamicTypeSize, typeSize) }
    }
    private func react(_ value: String?) async {
        busy = true; defer { busy = false }
        do {
            var fields: [String: JSONValue] = ["noteId": .string(shown.id)]
            if let value { fields["reaction"] = .string(value) }
            _ = try await session.call(value == nil ? "notes/reactions/delete" : "notes/reactions/create", fields, mutation: true)
            current = Record(try await session.call("notes/show", ["noteId": .string(shown.id)])); error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func renote() async {
        busy = true; defer { busy = false }
        do { _ = try await session.call("notes/create", ["renoteId": .string(shown.id)], mutation: true); error = "已转发" }
        catch { self.error = error.localizedDescription }
    }
}

struct NoteDetailView: View {
    @Environment(AppSession.self) private var session
    let noteID: String
    @State private var note: Record?
    @State private var replies: [Record] = []
    @State private var error: String?
    var body: some View {
        List {
            if let note { NoteCard(note: note, detail: true) }
            if let error { ErrorBanner(message: error) { Task { await load() } } }
            Section("回复") { ForEach(replies) { NoteCard(note: $0) } }
        }.puboList().navigationTitle("帖子").task { await load() }.refreshable { await load() }
    }
    private func load() async {
        do {
            note = Record(try await session.call("notes/show", ["noteId": .string(noteID)]))
            replies = Record.list(try await session.call("notes/replies", ["noteId": .string(noteID), "limit": .number(30)])); error = nil
        } catch { self.error = error.localizedDescription }
    }
}

