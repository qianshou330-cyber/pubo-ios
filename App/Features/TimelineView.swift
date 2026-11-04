import SwiftUI
import PUBOCore

struct TimelineCache: Codable { let savedAt: Date; let notes: [Record] }
private struct TimelineOffset: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct TimelineView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var feed = TimelineState()
    @State private var error: String?
    @State private var loading = false
    @State private var hasMore = true
    @State private var composer = false
    @State private var requestID = UUID()
    @State private var requestContext = ""
    @State private var cached = false
    @State private var homeRefresh = 0
    @State private var firstLoadFinished = false
    @State private var homePath: [HomeDestination] = []
    @State private var songSelection: ChartSongSelection?
    @State private var atTop = true
    @State private var anchor: String?
    @State private var visibleIDs = Set<String>()
    @State private var reconnectingContext: String?
    @State private var detailCollection: CollectionKind?
    private var preferences: TimelinePreferences { session.timelinePreferences }
    private var choices: [String] { HomeContent.timelines(user: session.user?.raw ?? .null) }
    private var active: Bool { session.selectedTab == 0 && scenePhase == .active }
    private var context: String { session.generation.uuidString + preferences.requestKey }
    private var motion: Bool { !reduceMotion && !ProcessInfo.processInfo.arguments.contains("--reduce-motion") }
    private var selection: Binding<String> { Binding(get: { preferences.selected }, set: { session.timelinePreferences.selected = $0; session.saveTimelinePreferences() }) }

    var body: some View {
        NavigationStack(path: $homePath) {
            ScrollViewReader { reader in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        Color.clear.frame(height: 1).id("timeline-top").background(GeometryReader { g in
                            Color.clear.preference(key: TimelineOffset.self, value: g.frame(in: .named("timeline")).minY)
                        })
                        VStack(spacing: 6) {
                            HomeAnnouncements(refreshID: homeRefresh) { homePath.append($0) }
                            HomeChartPanel(refreshID: homeRefresh) { destination in
                                if case .history(let key, let song, let chart) = destination { songSelection = ChartSongSelection(key: key, song: song, chart: chart) }
                                else { homePath.append(destination) }
                            }
                        }.padding(.horizontal, 12).padding(.vertical, 8).id("timeline-panels")
                        if preferences.fixedComposer && !composer { ComposeView(embedded: true) { Task { await load() } }.frame(minHeight: 180).id("timeline-composer") }
                        if let notice = session.timelineNotice { Text(notice).font(.caption).foregroundStyle(PUBOTheme.secondary).padding(10) }
                        if cached { Text("显示本机缓存，正在获取最新内容").font(.caption).foregroundStyle(.secondary) }
                        if let error { ErrorBanner(message: error) { Task { await load(older: firstLoadFinished) } }.padding(12) }
                        if feed.notes.isEmpty && !firstLoadFinished && error == nil { ForEach(0..<3) { _ in PostLoadingSkeleton().padding(12) } }
                        ForEach(Array(feed.notes.enumerated()), id: \.element.id) { index, note in
                            VStack(spacing: 0) {
                                if index > 0 && day(note) != day(feed.notes[index - 1]) { Text(day(note)).font(.caption).foregroundStyle(PUBOTheme.secondary).padding(10).frame(maxWidth: .infinity) }
                                NoteCard(note: note, timelineStyle: true, hideSensitive: !preferences.withSensitive)
                            }.id(note.id)
                                .transition(.asymmetric(insertion: .offset(y: -64).combined(with: .opacity), removal: .opacity.combined(with: .scale(scale: 0.01, anchor: .top))))
                                .onAppear { visibleIDs.insert(note.id); captureVisible(); if index >= feed.notes.count - 5 && hasMore && error == nil { Task { await load(older: true) } } }
                                .onDisappear { visibleIDs.remove(note.id); captureVisible() }
                        }
                        if loading && !feed.notes.isEmpty { ProgressView().padding() }
                        if feed.notes.isEmpty && firstLoadFinished && !loading && error == nil { Text("暂时没有帖子").foregroundStyle(.secondary).padding(30) }
                        if !hasMore && !feed.notes.isEmpty { Text("已显示全部帖子").font(.caption).foregroundStyle(.secondary).padding(16) }
                        Color.clear.frame(height: 68)
                    }.scrollTargetLayout()
                }.coordinateSpace(name: "timeline").scrollPosition(id: $anchor, anchor: .top)
                    .onPreferenceChange(TimelineOffset.self) { atTop = $0 > -80 }
                    .overlay(alignment: .top) {
                        if !feed.pending.isEmpty {
                            Button { feed.revealPending(); withAnimation(motion ? .easeOut(duration: 0.25) : nil) { reader.scrollTo("timeline-top", anchor: .top) } } label: {
                                Label("新帖子 \(feed.pending.count)", systemImage: "arrow.up.circle").font(.subheadline).padding(.horizontal, 16).padding(.vertical, 10).background(PUBOTheme.accent, in: Capsule()).foregroundStyle(PUBOTheme.panel)
                            }.padding(8).accessibilityIdentifier("timeline.newPosts")
                        }
                    }
                    .refreshable { homeRefresh += 1; await load() }
                    .simultaneousGesture(DragGesture(minimumDistance: 60).onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) * 2,
                              let index = choices.firstIndex(of: preferences.selected) else { return }
                        let next = index + (value.translation.width < 0 ? 1 : -1)
                        if choices.indices.contains(next) { selection.wrappedValue = choices[next] }
                    })
            }.puboScreen().toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: HomeDestination.self) { $0.view }
                .safeAreaInset(edge: .top, spacing: 0) { header }
                .overlay(alignment: .bottomTrailing) {
                    Button { composer = true } label: { Image(systemName: "pencil").font(.title3.bold()).foregroundStyle(.white).frame(width: 48, height: 48).background(PUBOTheme.accent, in: Circle()).shadow(color: .black.opacity(0.12), radius: 4, y: 2) }
                        .buttonStyle(.plain).padding(16).accessibilityLabel("发帖").accessibilityIdentifier("home.compose")
                }
                .sheet(isPresented: $composer) { ComposeView { Task { await load() } }.environment(\.dynamicTypeSize, typeSize) }
                .sheet(item: $songSelection) { ChartSongSheet(selection: $0) }
                .task(id: context) {
                    requestID = UUID(); feed.reset(); visibleIDs = []; hasMore = true; cached = false; firstLoadFinished = false; error = nil; loading = false
                    session.stream.showTimeline(preferences.selected, parameters: preferences.parameters)
                    if let owner = session.user?.id, let saved = try? session.store?.read(TimelineCache.self, account: "public-" + owner, key: "timeline-" + preferences.requestKey), Date().timeIntervalSince(saved.savedAt) < 86_400 {
                        feed.page(saved.notes, older: false, preferences: preferences, accountID: owner); cached = !saved.notes.isEmpty
                    }
                    await load()
                }
                .onDisappear { requestID = UUID(); session.stream.showTimeline(nil); session.stream.captureNotes([]) }
                .onAppear { session.stream.showTimeline(preferences.selected, parameters: preferences.parameters) }
                .onChange(of: session.newestTimelineNote) { _, note in
                    guard active, let note else { return }
                    withAnimation(motion && atTop ? .timingCurve(0.23, 1, 0.32, 1, duration: 0.7) : nil) { feed.receive(note, atTop: atTop, preferences: preferences, accountID: session.user?.id) }
                }
                .onChange(of: session.latestNoteEvent) { _, event in
                    guard let event else { return }
                    withAnimation(motion && event.kind == "deleted" ? .timingCurve(0, 0.5, 0.5, 1, duration: 0.2) : nil) { feed.apply(event, accountID: session.user?.id) }
                }
                .onChange(of: choices) { _, available in session.timelinePreferences.normalize(available: available) }
                .onChange(of: session.connectionRevision) { _, _ in if active { Task { await reconnect() } } }
                .onChange(of: active) { _, value in if value { Task { await reconnect() } } else { session.stream.captureNotes([]) } }
                .onChange(of: preferences) { _, _ in session.saveTimelinePreferences() }
        }
    }
    private var header: some View {
        HStack(spacing: 0) {
            if let user = session.user { NavigationLink { ProfileView(userID: user.id) } label: { Avatar(user: user, size: 28).frame(width: 40, height: 44) }.accessibilityLabel("我的主页") }
            ScrollView(.horizontal) { HStack(spacing: 0) {
                PUBOTimelineSelector(selection: selection, available: choices, compact: true).frame(minWidth: 210)
                NavigationLink { CollectionsView(kind: .list) } label: { Image(systemName: "list.bullet").frame(width: 44, height: 44) }.accessibilityLabel("列表")
                NavigationLink { CollectionsView(kind: .antenna) } label: { Image(systemName: "antenna.radiowaves.left.and.right").frame(width: 44, height: 44) }.accessibilityLabel("天线")
                NavigationLink { CollectionsView(kind: .channel) } label: { Image(systemName: "tv").frame(width: 44, height: 44) }.accessibilityLabel("频道")
            } }.scrollIndicators(.hidden)
            Menu {
                Toggle("显示转帖", isOn: Binding(get: { preferences.withRenotes }, set: { session.timelinePreferences.withRenotes = $0 }))
                if ["local", "hybrid"].contains(preferences.selected) { Toggle("在时间线中显示对他人的回复", isOn: Binding(get: { preferences.withReplies }, set: { session.timelinePreferences.setReplies($0) })) }
                Toggle("显示包含敏感媒体的帖子", isOn: Binding(get: { preferences.withSensitive }, set: { session.timelinePreferences.withSensitive = $0 }))
                Toggle("仅限媒体", isOn: Binding(get: { preferences.onlyFiles }, set: { session.timelinePreferences.setOnlyFiles($0) }))
                Toggle("在时间线顶部显示发帖框", isOn: Binding(get: { preferences.fixedComposer }, set: { session.timelinePreferences.fixedComposer = $0 }))
                Divider()
                NavigationLink("搜索") { SearchView() }; NavigationLink("站内公告") { AnnouncementsView() }
                NavigationLink("我的收藏") { FavoritesView() }; NavigationLink("更多功能") { MoreSocialView() }
                Link("在网页查看时间线", destination: Endpoint.origin)
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--timeline-events") {
                    Button("测试新帖") { var fields = TimelineTestFixtures.snapshot["posts"].array[0].object; fields["id"] = .string("zznewtimeline0001"); fields["text"] = .string("实时新帖，不打断历史阅读"); session.newestTimelineNote = Record(.object(fields)) }
                    Button("测试删除原帖") { session.latestNoteEvent = .init(id: "at4tltest0025", kind: "deleted", body: .null) }
                    Button("测试断线恢复") { session.connectionRevision += 1 }
                }
                #endif
            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                .accessibilityLabel("首页更多").accessibilityIdentifier("home.more")
        }.font(.caption).buttonStyle(.plain).foregroundStyle(PUBOTheme.secondary).background(PUBOTheme.panel).overlay(alignment: .bottom) { Rectangle().fill(PUBOTheme.divider).frame(height: 0.5) }
    }
    private func day(_ note: Record) -> String { guard let date = puboDate(note["createdAt"].string) else { return "" }; return date.formatted(.dateTime.month().day()) }
    private func captureVisible() { session.stream.captureNotes(active ? TimelinePresentation.capturedIDs(feed.notes.filter { visibleIDs.contains($0.id) }) : []) }
    private func reconnect() async {
        let reconnectContext = context
        guard reconnectingContext != reconnectContext else { return }
        reconnectingContext = reconnectContext
        defer { if reconnectingContext == reconnectContext { reconnectingContext = nil } }
        session.stream.showTimeline(preferences.selected, parameters: preferences.parameters)
        captureVisible()
        let epoch = session.generation, request = context, priorNewest = feed.notes.first?.id
        if let priorNewest {
            var cursor: String?; var finished = false; var pages = 0
            repeat {
                var fields = preferences.parameters; fields["limit"] = .number(100)
                if let cursor { fields["untilId"] = .string(cursor) }
                do {
                    let rows = Record.list(try await session.call("notes/\(preferences.selected)-timeline", fields))
                    guard epoch == session.generation, context == request, !Task.isCancelled else { return }
                    for row in rows where row.id > priorNewest { feed.receive(row, atTop: atTop, preferences: preferences, accountID: session.user?.id) }
                    finished = rows.count < 100 || (rows.last?.id ?? "") <= priorNewest
                    cursor = rows.last?.id; pages += 1
                } catch { self.error = "重连后补取失败，已保留现有帖子。"; return }
            } while !finished && pages < 20
            if !finished { session.timelineNotice = "离线期间帖子较多，已获取最近内容；可向下继续加载历史。" }
        } else { await load() }
        for id in TimelinePresentation.capturedIDs(feed.notes.filter { visibleIDs.contains($0.id) }).sorted().prefix(30) {
            guard active, !Task.isCancelled, epoch == session.generation, context == request else { return }
            do {
                let value = Record(try await session.call("notes/show", ["noteId": .string(id)]))
                guard epoch == session.generation, context == request, active else { return }
                // Full records refresh their containing quote/reply without discarding reference data.
                session.latestNoteEvent = .init(id: id, kind: "replaced", body: value.raw)
            } catch { if (error as? APIError)?.code == "NO_SUCH_NOTE" { session.latestNoteEvent = .init(id: id, kind: "deleted", body: .null) } }
        }
    }
    private func load(older: Bool = false) async {
        guard !loading || requestContext != context else { return }
        guard !older || hasMore else { return }
        let attempt = UUID(), currentContext = context, selected = preferences
        requestID = attempt; requestContext = currentContext; loading = true
        defer { if requestID == attempt { loading = false } }
        var fields = selected.parameters; fields["limit"] = .number(20)
        if older, let id = feed.olderCursor { fields["untilId"] = .string(id) }
        do {
            let result = Record.list(try await session.call("notes/\(selected.selected)-timeline", fields))
            try Task.checkCancellation(); guard requestID == attempt, context == currentContext else { return }
            if older || atTop || feed.notes.isEmpty { feed.page(result, older: older, preferences: selected, accountID: session.user?.id) }
            else { for note in result { feed.receive(note, atTop: false, preferences: selected, accountID: session.user?.id) } }
            if older || !firstLoadFinished { hasMore = result.count == 20 }
            error = nil; cached = false; firstLoadFinished = true
            if let owner = session.user?.id { try? session.store?.save(TimelineCache(savedAt: Date(), notes: Array(feed.notes.filter { $0["visibility"].string == "public" }.prefix(100))), account: "public-" + owner, key: "timeline-" + selected.requestKey) }
        } catch is CancellationError {} catch {
            guard requestID == attempt, context == currentContext else { return }
            if (error as? APIError)?.code == "LTL_DISABLED" { session.timelinePreferences.selected = "home"; session.timelineNotice = "本地时间线暂不可用，已切换到关注。" }
            else { self.error = error.localizedDescription; firstLoadFinished = true }
        }
    }
}

struct NoteCard: View {
    @Environment(\.openNoteCard) private var navigate
    @Environment(AppSession.self) private var session
    @Environment(\.dynamicTypeSize) private var typeSize
    let note: Record
    var detail = false
    var timelineStyle = false
    var hideSensitive = false
    @State private var revealCW = false
    @State private var revealSensitivePost = false
    @State private var confirmReaction = false
    @State private var proposedReaction: String?
    @State private var reactionPulse = false
    @State private var captureOwner = UUID().uuidString
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reactionPicker = false
    @State private var replying = false
    @State private var quoting = false
    @State private var error: String?
    @State private var current: Record?
    @State private var busy = false
    @State private var reporting = false
    @State private var confirmDelete = false
    @State private var confirmBlock = false
    @State private var selectingClip = false
    @State private var viewingReactions = false
    private var shown: Record { NoteContext.displayed(current ?? note) }
    private var ownDeleteID: String? { note.user.id == session.user?.id ? note.id : shown.user.id == session.user?.id ? shown.id : nil }
    var body: some View { if !session.deletedNoteIDs.contains(note.id) && !session.deletedNoteIDs.contains(shown.id) { content } }
    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            if NoteContext.isRepost(note) {
                Button { navigate(.author(note.user.id)) } label: { Label(note.user.displayName + " 转发了", systemImage: "arrow.2.squarepath").font(.caption).frame(minHeight: 28) }.buttonStyle(.plain).foregroundStyle(PUBOTheme.secondary)
            }
            if !shown["replyId"].isNull || !shown["reply"]["id"].isNull {
                NoteContextCard(value: shown["reply"], targetID: shown["replyId"].string, label: "回复")
            }
            HStack(alignment: .top, spacing: 10) {
                Button { navigate(.author(shown.user.id)) } label: { Avatar(user: shown.user, size: 44) }.buttonStyle(.plain).accessibilityLabel(shown.user.displayName + "的头像")
                VStack(alignment: .leading, spacing: 4) {
                    authorHeader
                    if hideSensitive && TimelinePresentation.sensitive(shown) && !revealSensitivePost {
                        Button("已折叠含敏感媒体的帖子 · 展开") { revealSensitivePost = true }.font(.caption).frame(minHeight: 44)
                    } else {
                        if let cw = shown["cw"].string {
                            Button { revealCW.toggle() } label: { Label(cw.isEmpty ? "内容警告 · 点击展开" : cw, systemImage: revealCW ? "eye.slash" : "eye").frame(minHeight: 44) }.buttonStyle(.plain).accessibilityValue(revealCW ? "已展开" : "已隐藏")
                        }
                        if shown["cw"].isNull || revealCW {
                            NoteText(text: shown.text, remoteEmojis: shown["emojis"], onTap: detail ? nil : { navigate(.note(shown.id)) }, identifier: "note.open." + shown.id)
                            PublicMediaGrid(files: Record.list(shown["files"]), noteID: shown.id)
                            if !shown["poll"].isNull { PollView(noteID: shown.id, initial: shown["poll"]).id(shown.id).disabled(session.user == nil) }
                            if !shown["renoteId"].isNull || !shown["renote"]["id"].isNull { NoteContextCard(value: shown["renote"], targetID: shown["renoteId"].string, label: "引用") }
                            NoteLinkPreviews(text: shown.text, active: true)
                            if shown.text.contains("$[") { Link("在网页查看完整内容", destination: Endpoint.origin.appendingPathComponent("notes/" + shown.id)).font(.caption) }
                        }
                        reactions
                    }
                    actions
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.font(.system(size: 14)).padding(.horizontal, 16).padding(.vertical, 12)
            .background(PUBOTheme.panel).overlay(alignment: .bottom) { Rectangle().fill(PUBOTheme.divider).frame(height: 0.5) }
            .listRowInsets(EdgeInsets()).listRowSeparator(.hidden).listRowBackground(Color.clear)
            .contextMenu { Link("在本站网页打开原帖", destination: Endpoint.origin.appendingPathComponent("notes/" + shown.id)) }
            .onChange(of: note) { _, _ in current = nil }
            .onAppear { if !timelineStyle { session.stream.captureNotes(TimelinePresentation.capturedIDs([note]), owner: captureOwner) } }
            .onDisappear { if !timelineStyle { session.stream.captureNotes([], owner: captureOwner) }; revealSensitivePost = false }
            .onChange(of: hideSensitive) { _, _ in revealSensitivePost = false }
            .onChange(of: session.latestNoteEvent) { _, event in
                guard !timelineStyle, let event else { return }
                current = event.applying(to: current ?? note, accountID: session.user?.id)
                if event.kind == "deleted" { session.deletedNoteIDs.insert(event.id) }
            }
            .confirmationDialog(proposedReaction == nil ? "取消这个表情反应？" : "更换表情反应？", isPresented: $confirmReaction) { Button(proposedReaction == nil ? "取消反应" : "更换反应") { Task { await react(proposedReaction) } } }
            .sheet(isPresented: $reactionPicker) { ReactionPicker { reaction in
                proposedReaction = reaction
                if shown["myReaction"].string != nil { confirmReaction = true } else { Task { await react(reaction) } }
            } }
            .sheet(isPresented: $replying) { ComposeView(replyTo: shown) { }.environment(\.dynamicTypeSize, typeSize) }
            .sheet(isPresented: $quoting) { ComposeView(renote: shown) { }.environment(\.dynamicTypeSize, typeSize) }
            .sheet(isPresented: $reporting) { ReportView(userID: shown.user.id, context: Endpoint.origin.appendingPathComponent("notes/" + shown.id).absoluteString) }
            .sheet(isPresented: $selectingClip) { ClipPicker(noteID: shown.id) }
            .sheet(isPresented: $viewingReactions) { NavigationStack { ReactionDetailsView(noteID: shown.id).toolbar { Button("关闭") { viewingReactions = false } } } }
            .confirmationDialog("删除后无法恢复这条帖子。", isPresented: $confirmDelete) { Button("删除帖子", role: .destructive) { Task { await deleteNote() } } }
            .confirmationDialog("屏蔽此用户？", isPresented: $confirmBlock) { Button("屏蔽", role: .destructive) { Task { do { _ = try await session.call("blocking/create", ["userId": .string(shown.user.id)], mutation: true); error = "已屏蔽" } catch { self.error = error.localizedDescription } } } }

    }
    private var authorHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Button { navigate(.author(shown.user.id)) } label: {
                HStack(spacing: 3) {
                    Text(shown.user.displayName).font(.system(size: 14, weight: .bold)).lineLimit(1)
                    if shown.user["isBot"].bool { Text("bot").font(.system(size: 9)).padding(.horizontal, 2).overlay(RoundedRectangle(cornerRadius: 2).stroke(PUBOTheme.divider)) }
                    Text("@" + (shown.user["username"].string ?? "")).font(.system(size: 12)).foregroundStyle(PUBOTheme.secondary).lineLimit(1)
                    UserInlineBadges(user: shown.user)
                }
            }.buttonStyle(.plain).accessibilityIdentifier("note.author." + shown.id)
            Spacer(minLength: 0)
            Button { navigate(.note(shown.id)) } label: {
                HStack(spacing: 3) {
                    if let date = puboDate(shown["createdAt"].string) { Text(date, style: .relative).lineLimit(1) }
                    if shown["visibility"].string != "public" { Image(systemName: TimelinePresentation.visibilityIcon(shown["visibility"].string)) }
                    if shown["localOnly"].bool { Image(systemName: "network.slash").accessibilityLabel("仅本站") }
                }.font(.system(size: 10)).foregroundStyle(PUBOTheme.secondary)
            }.buttonStyle(.plain).accessibilityLabel("查看帖子时间和详情，" + TimelinePresentation.visibilityLabel(shown["visibility"].string)).accessibilityIdentifier("note.timestamp." + shown.id)
        }.frame(minHeight: 22)
    }
    private var actions: some View {
        Group {
            if session.user != nil { HStack(spacing: 12) {
                Button { replying = true } label: { HStack(spacing: 4) { Image(systemName: "arrowshape.turn.up.left"); if shown["repliesCount"].int > 0 { Text("\(shown["repliesCount"].int)").font(.caption) } }.frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("回复")
                Menu {
                    Button("转发") { Task { await renote() } }
                    Button("引用转发") { quoting = true }
                } label: { HStack(spacing: 3) { Image(systemName: "arrow.2.squarepath"); if shown["renoteCount"].int > 0 { Text("\(shown["renoteCount"].int)").font(.caption2) } }.frame(minWidth: 44, minHeight: 44) }
                Button { reactionPicker = true } label: { Image(systemName: "plus").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("添加表情反应")
                if !shown["myReaction"].isNull { Button("取消反应") { proposedReaction = nil; confirmReaction = true }.font(.caption) }
                Spacer(minLength: 0)
                Menu {
                    Button("收藏帖子") { Task { await favorite(true) } }
                    Button("取消收藏") { Task { await favorite(false) } }
                    Button("加入剪藏") { selectingClip = true }
                    Button("查看反应详情") { viewingReactions = true }
                    if ownDeleteID != nil { Button("删除帖子", role: .destructive) { confirmDelete = true } }
                    if let id = ownDeleteID { Button((session.user?["pinnedNoteIds"].array.compactMap(\.string) ?? []).contains(id) ? "取消置顶帖子" : "置顶到个人主页") { Task { await pin(id) } } }
                    if shown.user.id != session.user?.id { Button("举报帖子") { reporting = true }; Button("屏蔽作者", role: .destructive) { confirmBlock = true } }
                    Link("在网页打开原帖", destination: Endpoint.origin.appendingPathComponent("notes/" + shown.id))
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("帖子更多操作")
            }.buttonStyle(.borderless).foregroundStyle(PUBOTheme.secondary).disabled(busy)
            } else { Text("登录后可回复、转发或添加反应").font(.caption).foregroundStyle(.secondary) }

        }.font(.system(size: 15))
    }
    private var reactions: some View {
        FlowReactionLayout {
            ForEach(shown["reactions"].object.keys.sorted(), id: \.self) { reaction in
                Button {
                    let previous = shown["myReaction"].string
                    if previous != nil { proposedReaction = previous == reaction ? nil : reaction; confirmReaction = true }
                    else { Task { await react(reaction) } }
                } label: {
                    HStack(spacing: 4) {
                        ReactionImage(reaction: reaction, emojis: shown["reactionEmojis"])
                        Text("\(shown["reactions"][reaction].int)").font(.system(size: 12, weight: .medium))
                    }.padding(.horizontal, 7).padding(.vertical, 5)
                        .background(shown["myReaction"].string == reaction ? PUBOTheme.accent.opacity(0.22) : PUBOTheme.button, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(shown["myReaction"].string == reaction ? PUBOTheme.accent : .clear))
                        .scaleEffect(reactionPulse && shown["myReaction"].string == reaction ? 1.16 : 1)
                }.buttonStyle(.plain).disabled(busy || session.user == nil).accessibilityLabel(reaction + " \(shown["reactions"][reaction].int)").accessibilityIdentifier("note.reaction." + shown.id + "." + reaction)
            }
        }
    }
    private func favorite(_ wanted: Bool) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            let state = try await session.call("notes/state", ["noteId": .string(shown.id)])
            if state["isFavorited"].bool != wanted { _ = try await session.call(wanted ? "notes/favorites/create" : "notes/favorites/delete", ["noteId": .string(shown.id)], mutation: true) }
            error = wanted ? "已收藏" : "已取消收藏"
        } catch { self.error = error.localizedDescription }
    }
    private func pin(_ id: String) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        let wanted = !(session.user?["pinnedNoteIds"].array.compactMap(\.string) ?? []).contains(id)
        do {
            do { _ = try await session.call(wanted ? "i/pin" : "i/unpin", ["noteId": .string(id)], mutation: true) }
            catch { if (error as? APIError)?.code != "OUTCOME_UNKNOWN" { throw error } }
            try await session.refreshUser()
            guard (session.user?["pinnedNoteIds"].array.compactMap(\.string) ?? []).contains(id) == wanted else { throw APIError.uncertain }
            error = wanted ? "已置顶到个人主页" : "已取消置顶"
        } catch { self.error = error.localizedDescription }
    }
    private func deleteNote() async {
        guard !busy, let id = ownDeleteID else { return }; busy = true; defer { busy = false }
        do { _ = try await session.call("notes/delete", ["noteId": .string(id)], mutation: true); session.deletedNoteIDs.insert(id) }
        catch {
            if (error as? APIError)?.code == "OUTCOME_UNKNOWN" {
                do { _ = try await session.call("notes/show", ["noteId": .string(id)]); self.error = APIError.uncertain.message }
                catch { if (error as? APIError)?.code == "NO_SUCH_NOTE" { session.deletedNoteIDs.insert(id) } else { self.error = error.localizedDescription } }
            } else { self.error = error.localizedDescription }
        }
    }
    private func react(_ value: String?) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        let id = shown.id
        do {
            let before = try await session.call("notes/show", ["noteId": .string(id)])
            let previous = before["myReaction"].string
            if previous != value {
                if previous != nil { _ = try await session.call("notes/reactions/delete", ["noteId": .string(id)], mutation: true) }
                if let value { _ = try await session.call("notes/reactions/create", ["noteId": .string(id), "reaction": .string(value)], mutation: true) }
            }
            current = Record(try await session.call("notes/show", ["noteId": .string(id)])); error = nil
            if value != nil && !reduceMotion {
                withAnimation(.spring(response: 0.18, dampingFraction: 0.6)) { reactionPulse = true }
                try? await Task.sleep(for: .milliseconds(180)); withAnimation(.easeOut(duration: 0.2)) { reactionPulse = false }
            }
        } catch {
            let failure = error
            if let verified = try? await session.call("notes/show", ["noteId": .string(id)]) {
                current = Record(verified)
                self.error = verified["myReaction"].string == value ? nil : "反应未完成，已核对当前状态，请重试。"
            } else { self.error = failure.localizedDescription }
        }
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
    @State private var more = true
    @State private var busy = false
    var body: some View {
        List {
            if let note { NoteCard(note: note, detail: true) }
            if let error { ErrorBanner(message: error) { Task { await load() } } }
            Section("回复") { ForEach(replies) { NoteCard(note: $0) }; if more { Button("加载更多回复") { Task { await load(older: true) } }.disabled(busy) } }
        }.puboList().navigationTitle("帖子").task { await load() }.refreshable { await load() }
    }
    private func load(older: Bool = false) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            if !older { note = Record(try await session.call("notes/show", ["noteId": .string(noteID)])) }
            var fields: [String: JSONValue] = ["noteId": .string(noteID), "limit": .number(30)]
            if older, let id = replies.last?.id { fields["untilId"] = .string(id) }
            let result = Record.list(try await session.call("notes/replies", fields))
            replies = older ? Records.merge(replies, result, limit: 10_000) : result; more = result.count == 30; error = nil
        } catch { self.error = error.localizedDescription }
    }
}

