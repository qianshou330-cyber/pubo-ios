import SwiftUI
import PUBOCore

struct TimelineCache: Codable {
    let savedAt: Date
    let notes: [Record]
}

struct TimelineView: View {
    @Environment(AppSession.self) private var session
    @State private var timeline = "home"
    @State private var notes: [Record] = []
    @State private var error: String?
    @State private var loading = false
    @State private var hasMore = true
    @State private var composer = false
    @State private var requestID = UUID()
    @State private var requestTimeline = ""
    @State private var cached = false

    var body: some View {
        NavigationStack {
            List {
                PUBOTimelineSelector(selection: $timeline).puboListRow()
                if cached { Text("显示本机缓存，正在获取最新内容").font(.caption).foregroundStyle(.secondary) }
                if let error { ErrorBanner(message: error) { Task { await load() } } }
                ForEach(notes) { note in NoteCard(note: note) }
                if loading { ProgressView().frame(maxWidth: .infinity) }
                if notes.isEmpty && !loading && error == nil { Text("暂时没有帖子").foregroundStyle(.secondary) }
                if hasMore && !notes.isEmpty { Button("加载更早的帖子") { Task { await load(older: true) } }.disabled(loading) }
            }.puboList().navigationTitle("动态")
                .toolbar { Button { composer = true } label: { Label("发帖", systemImage: "square.and.pencil") }.buttonStyle(PUBOButtonStyle(kind: .publish)).accessibilityLabel("发帖") }
                .sheet(isPresented: $composer) { ComposeView { Task { await load() } } }
                .refreshable { await load() }
                .task(id: timeline) {
                    session.stream.showTimeline(timeline)
                    notes = []; hasMore = true; cached = false
                    if let owner = session.user?.id, let saved = try? session.store?.read(TimelineCache.self, account: "public-" + owner, key: "timeline-" + timeline), !saved.notes.isEmpty, Date().timeIntervalSince(saved.savedAt) < 86_400 { notes = saved.notes; cached = true }
                    await load()
                }
                .onAppear { session.stream.showTimeline(timeline) }
                .onDisappear { session.stream.showTimeline(nil) }
                .task(id: session.streamRevision) {
                    guard session.selectedTab == 0 else { return }
                    try? await Task.sleep(for: .milliseconds(700))
                    if !Task.isCancelled { await load() }
                }
        }
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
            guard selected == timeline, requestID == attempt else { return }
            notes = Records.merge(notes, result, limit: 2_000); error = nil; cached = false
            if let owner = session.user?.id { try? session.store?.save(TimelineCache(savedAt: Date(), notes: Array(notes.filter { $0["visibility"].string == "public" }.prefix(100))), account: "public-" + owner, key: "timeline-" + selected) }
            if older || notes.count <= 20 { hasMore = result.count == 20 && notes.count < 2_000 }
        } catch is CancellationError { } catch { self.error = error.localizedDescription }
    }
}

struct NoteCard: View {
    @Environment(AppSession.self) private var session
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
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink { ProfileView(userID: shown.user.id) } label: {
                HStack { Avatar(user: shown.user, size: 42); VStack(alignment: .leading) { Text(shown.user.displayName).font(.headline); Text("@" + (shown.user["username"].string ?? "")).font(.caption).foregroundStyle(.secondary) }; Spacer(); if let date = puboDate(shown["createdAt"].string) { Text(date, style: .relative).font(.caption2).foregroundStyle(PUBOTheme.secondary).lineLimit(1) } }
            }.buttonStyle(.plain)
            if let cw = shown["cw"].string { Button { revealCW.toggle() } label: { Label(cw.isEmpty ? "内容警告 · 点击展开" : cw, systemImage: revealCW ? "eye.slash" : "eye") } }
            if shown["cw"].isNull || revealCW {
                NoteText(text: shown.text, remoteEmojis: shown["emojis"])
                ForEach(Record.list(shown["files"])) { file in PublicMedia(file: file) }
                if !shown["poll"].isNull || shown.text.contains("$[") { Link("在网页查看完整内容", destination: Endpoint.origin.appendingPathComponent("notes/" + shown.id)).font(.caption) }
            }
            if !detail { NavigationLink("查看帖子与回复") { NoteDetailView(noteID: shown.id) }.font(.caption) }
            HStack(spacing: 12) {
                Button { replying = true } label: { Image(systemName: "arrowshape.turn.up.left").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("回复")
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
        }.puboCard().puboListRow()
            .contextMenu { Link("在本站网页打开原帖", destination: Endpoint.origin.appendingPathComponent("notes/" + shown.id)) }
            .sheet(isPresented: $reactionPicker) { ReactionPicker { reaction in Task { await react(reaction) } } }
            .sheet(isPresented: $replying) { ComposeView(replyTo: shown) { } }
            .sheet(isPresented: $quoting) { ComposeView(renote: shown) { } }
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
