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
    @Environment(\.timelineWindowTypeSize) private var feedTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var feed = TimelineState()
    @State private var error: String?
    @State private var failedOlderRequest = false
    @State private var loading = false
    @State private var hasMore = true
    @State private var composer = false
    @State private var requestID = UUID()
    @State private var requestContext = ""
    @State private var cached = false
    @State private var homeRefresh = 0
    @State private var firstLoadFinished = false
    @State private var firstPageLoaded = false
    @State private var homePath: [HomeDestination] = []
    @State private var songSelection: ChartSongSelection?
    @State private var atTop = true
    @State private var anchor: String?
    @State private var visibleIDs = Set<String>()
    @State private var reconnectingContext: String?
    @State private var reconnectAttempt = UUID()
    @State private var reconnectTask: Task<Void, Never>?
    @State private var pageVisible = false
    @State private var detailCollection: CollectionKind?
    private var preferences: TimelinePreferences { session.timelinePreferences }
    private var choices: [String] { HomeContent.timelines(user: session.user?.raw ?? .null) }
    private var active: Bool { pageVisible && session.selectedTab == 0 && scenePhase == .active }
    private var context: String { session.generation.uuidString + preferences.requestKey }
    private var motion: Bool { !reduceMotion && !ProcessInfo.processInfo.arguments.contains("--reduce-motion") }
    private var selection: Binding<String> { Binding(get: { preferences.selected }, set: { session.timelinePreferences.selected = $0; session.saveTimelinePreferences() }) }

    var body: some View {
        NavigationStack(path: $homePath) {
            lifecycleContent
        }
    }
    private var lifecycleContent: some View {
        presentedContent.task(id: context) { await prepareTimeline() }

                .onDisappear { pageVisible = false; requestID = UUID(); loading = false; reconnectTask?.cancel(); reconnectTask = nil; reconnectingContext = nil; reconnectAttempt = UUID(); session.stream.showTimeline(nil); session.stream.captureNotes([]) }
                .onAppear { pageVisible = true; session.stream.showTimeline(preferences.selected, parameters: preferences.parameters) }
                .onReceive(session.timelineNotes) { note in
                    guard active else { return }
                    withAnimation(motion && atTop ? .timingCurve(0.23, 1, 0.32, 1, duration: 0.7) : nil) { feed.receive(note, atTop: atTop, preferences: preferences, accountID: session.user?.id) }
                }
                .onReceive(session.noteEvents) { event in
                    withAnimation(motion && event.kind == "deleted" ? .timingCurve(0, 0.5, 0.5, 1, duration: 0.2) : nil) { feed.apply(event, accountID: session.user?.id) }
                }
                .onChange(of: choices) { _, available in
                    let lostLocal = preferences.selected == "local" && !available.contains("local")
                    session.timelinePreferences.normalize(available: available)
                    if lostLocal { session.timelineNotice = "本地时间线暂不可用，已切换到关注。" }
                }
                .onChange(of: session.connectionRevision) { _, _ in startReconnect() }
                .onChange(of: active) { _, value in
                    if value { startReconnect() }
                    else { reconnectTask?.cancel(); reconnectTask = nil; reconnectingContext = nil; reconnectAttempt = UUID(); session.stream.showTimeline(nil); session.stream.captureNotes([]) }
                }
                .onChange(of: preferences) { _, _ in session.saveTimelinePreferences() }
    }
    private var presentedContent: some View {
        timelineScroll.puboScreen().toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: HomeDestination.self) { $0.view }
                .safeAreaInset(edge: .top, spacing: 0) { header }
                .overlay(alignment: .bottomTrailing) {
                    Button { composer = true } label: { FeedIcon(name: "pencil").font(.title3.bold()).foregroundStyle(.white).frame(width: 48, height: 48).background(PUBOTheme.accent, in: Circle()).shadow(color: .black.opacity(0.12), radius: 4, y: 2) }
                        .buttonStyle(.plain).padding(16).accessibilityLabel("发帖").accessibilityIdentifier("home.compose")
                }
                .sheet(isPresented: $composer) { ComposeView { Task { await load() } }.environment(\.dynamicTypeSize, typeSize) }
                .sheet(item: $songSelection) { ChartSongSheet(selection: $0) }

    }
    private var timelineScroll: some View {
            ScrollViewReader { reader in
                ScrollView {
                    timelineContent
                }.accessibilityIdentifier("timeline.scroll").coordinateSpace(name: "timeline").scrollPosition(id: $anchor, anchor: .top)
                    .onPreferenceChange(TimelineOffset.self, perform: updateOffset)
                    .onChange(of: anchor) { _, id in updateAnchor(id) }
                    .overlay(alignment: .top) {
                        TimelinePendingButton(count: feed.pending.count) {
                            withAnimation(motion ? .timingCurve(0.23, 1, 0.32, 1, duration: 0.7) : nil) {
                                feed.revealPending(); reader.scrollTo("timeline-top", anchor: .top)
                            }
                        }
                    }
                    .refreshable {
                        #if DEBUG
                        RefreshDiagnostics.shared.record(.pullStarted)
                        defer { RefreshDiagnostics.shared.record(.pullEnded) }
                        #endif
                        homeRefresh += 1; await load()
                    }
                    .simultaneousGesture(DragGesture(minimumDistance: 60).onEnded(switchTimeline))
            }
    }
    private var timelineContent: some View {
        LazyVStack(spacing: 0) {
            timelineHeading
            timelineRows
            if let error, failedOlderRequest {
                ErrorBanner(message: "加载更早帖子失败：" + error, retryIdentifier: "timeline.retryOlder") { Task { await load(older: true) } }
                    .padding(12)
            }
            TimelineLoadingStatus(loading: loading, empty: feed.notes.isEmpty,
                loaded: firstLoadFinished, failed: error != nil, hasMore: hasMore)
            Color.clear.frame(height: 68)
        }.scrollTargetLayout().background(GeometryReader { g in
            Color.clear.preference(key: TimelineOffset.self, value: g.frame(in: .named("timeline")).minY)
        })
    }
    private var timelineHeading: some View {
        Group {
                        Color.clear.frame(height: 1).id("timeline-top")
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
                        if let error, !failedOlderRequest { ErrorBanner(message: error) { Task { await load() } }.padding(12).accessibilityIdentifier("timeline.refreshRetry") }
                        if feed.notes.isEmpty && !firstLoadFinished && error == nil { ForEach(0..<3) { _ in PostLoadingSkeleton().padding(12) } }
        }
    }
    private var timelineRows: some View {
                        ForEach(Array(feed.notes.enumerated()), id: \.element.id) { index, note in
                            TimelinePostRow(note: note, first: index == 0,
                                last: index == feed.notes.count - 1,
                                dateBreak: index > 0 && day(note) != day(feed.notes[index - 1]) ? day(note) : nil,
                                hideSensitive: !preferences.withSensitive)
                                .environment(\.dynamicTypeSize, feedTypeSize)
                                .id(note.id)
                                .transition(.asymmetric(insertion: .offset(y: -64).combined(with: .opacity), removal: .opacity))
                                .onAppear { appeared(note, index: index) }
                                .onDisappear { visibleIDs.remove(note.id); captureVisible() }
                        }
    }
    private func updateOffset(_ offset: CGFloat) {
        if anchor == nil || anchor == "timeline-top" || anchor == "timeline-panels" { atTop = offset > -80 }
    }
    private func updateAnchor(_ id: String?) {
        atTop = id == nil || id == "timeline-top" || id == "timeline-panels"
    }
    private func switchTimeline(_ value: DragGesture.Value) {
        guard abs(value.translation.width) > abs(value.translation.height) * 2,
              let index = choices.firstIndex(of: preferences.selected) else { return }
        let next = index + (value.translation.width < 0 ? 1 : -1)
        if choices.indices.contains(next) { selection.wrappedValue = choices[next] }
    }
    private func prepareTimeline() async {
                    guard !firstLoadFinished || requestContext != context else { return }
                    reconnectTask?.cancel(); reconnectTask = nil; reconnectingContext = nil; reconnectAttempt = UUID()
                    requestID = UUID(); feed.reset(); visibleIDs = []; hasMore = true; cached = false; firstLoadFinished = false; firstPageLoaded = false; error = nil; failedOlderRequest = false; loading = false
                    anchor = "timeline-top"; atTop = true
                    session.stream.showTimeline(preferences.selected, parameters: preferences.parameters)
                    if let owner = session.user?.id, let saved = try? session.store?.read(TimelineCache.self, account: "public-" + owner, key: "timeline-" + preferences.requestKey), Date().timeIntervalSince(saved.savedAt) < 86_400 {
                        feed.page(saved.notes, older: false, preferences: preferences, accountID: owner); cached = !saved.notes.isEmpty
                    }
                    await load()
    }
    private func appeared(_ note: Record, index: Int) {
        visibleIDs.insert(note.id)
        captureVisible()
        if index >= feed.notes.count - 5 && hasMore && error == nil {
            Task { await load(older: true, automatic: true) }
        }
    }
    private var header: some View {
        HStack(spacing: 0) {
            if let user = session.user {
                NavigationLink { ProfileView(userID: user.id) } label: {
                    Avatar(user: user, size: 28).frame(width: 44, height: 44).contentShape(Rectangle())
                }.accessibilityLabel("我的主页")
            }
            ScrollView(.horizontal) { HStack(spacing: 0) {
                PUBOTimelineSelector(selection: selection, available: choices, compact: true, appearance: .timeline)
                    .environment(\.dynamicTypeSize, feedTypeSize).frame(minWidth: 210)
                NavigationLink { CollectionsView(kind: .list) } label: { FeedIcon(name: "list").frame(width: 44, height: 44).contentShape(Rectangle()) }.accessibilityLabel("列表")
                NavigationLink { CollectionsView(kind: .antenna) } label: { FeedIcon(name: "antenna").frame(width: 44, height: 44).contentShape(Rectangle()) }.accessibilityLabel("天线")
                NavigationLink { CollectionsView(kind: .channel) } label: { FeedIcon(name: "device-tv").frame(width: 44, height: 44).contentShape(Rectangle()) }.accessibilityLabel("频道")
            } }.scrollIndicators(.hidden)
            Menu {
                Toggle("显示转帖", isOn: Binding(get: { preferences.withRenotes }, set: { session.timelinePreferences.withRenotes = $0 }))
                if ["local", "hybrid"].contains(preferences.selected) { Toggle("在时间线中显示对他人的回复", isOn: Binding(get: { preferences.withReplies }, set: { session.timelinePreferences.setReplies($0) })).disabled(preferences.onlyFiles) }
                Toggle("显示包含敏感媒体的帖子", isOn: Binding(get: { preferences.withSensitive }, set: { session.timelinePreferences.withSensitive = $0 }))
                Toggle("仅限媒体", isOn: Binding(get: { preferences.onlyFiles }, set: { session.timelinePreferences.setOnlyFiles($0) })).disabled(["local", "hybrid"].contains(preferences.selected) && preferences.withReplies)
                Toggle("在时间线顶部显示发帖框", isOn: Binding(get: { preferences.fixedComposer }, set: { session.timelinePreferences.fixedComposer = $0 }))
                Divider()
                NavigationLink("搜索") { SearchView() }; NavigationLink("站内公告") { AnnouncementsView() }
                NavigationLink("我的收藏") { FavoritesView() }; NavigationLink("更多功能") { MoreSocialView() }
                Link("在网页查看时间线", destination: Endpoint.origin)
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--timeline-events") {
                    Button("测试新帖") { var fields = TimelineTestFixtures.snapshot["posts"].array[0].object; fields["id"] = .string("zznewtimeline0001"); fields["createdAt"] = .string(ISO8601DateFormatter().string(from: Date())); fields["text"] = .string("实时新帖，不打断历史阅读"); session.newestTimelineNote = Record(.object(fields)) }
                    Button("测试删除原帖") { session.latestNoteEvent = .init(id: "at4tltest0025", kind: "deleted", body: .null) }
                    Button("测试断线恢复") { session.connectionRevision += 1 }
                }
                #endif
            } label: { FeedIcon(name: "dots").frame(width: 44, height: 44).contentShape(Rectangle()) }
                .accessibilityLabel("首页更多").accessibilityIdentifier("home.more")
        }.font(.caption).buttonStyle(.plain).foregroundStyle(PUBOTheme.secondary).background(PUBOTheme.panel).overlay(alignment: .bottom) { Rectangle().fill(PUBOTheme.divider).frame(height: 0.5) }
    }
    private func day(_ note: Record) -> String { guard let date = puboDate(note["createdAt"].string) else { return "" }; return date.formatted(.dateTime.month().day()) }
    private func captureVisible() { session.stream.captureNotes(active ? TimelinePresentation.capturedIDs(feed.notes.filter { visibleIDs.contains($0.id) }) : []) }
    private func startReconnect() {
        guard active, firstLoadFinished, reconnectingContext != context else { return }
        reconnectTask?.cancel()
        reconnectTask = Task { await reconnect() }
    }
    private func reconnect() async {
        let reconnectContext = context
        guard active, !Task.isCancelled, reconnectingContext != reconnectContext else { return }
        let attempt = UUID(); reconnectAttempt = attempt
        reconnectingContext = reconnectContext
        defer { if reconnectAttempt == attempt { reconnectingContext = nil } }
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
                    guard active, epoch == session.generation, context == request, !Task.isCancelled else { return }
                    for row in rows where row.id > priorNewest { feed.receive(row, atTop: atTop, preferences: preferences, accountID: session.user?.id) }
                    finished = rows.count < 100 || (rows.last?.id ?? "") <= priorNewest
                    cursor = rows.last?.id; pages += 1
                } catch { if active && !Task.isCancelled && epoch == session.generation && context == request { failedOlderRequest = false; self.error = "重连后补取失败，已保留现有帖子。" }; return }
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
            } catch {
                if active, !Task.isCancelled, epoch == session.generation, context == request,
                   (error as? APIError)?.code == "NO_SUCH_NOTE" { session.latestNoteEvent = .init(id: id, kind: "deleted", body: .null) }
            }
        }
    }
    private func load(older: Bool = false, automatic: Bool = false) async {
            #if DEBUG
            RefreshDiagnostics.shared.record(.loadAttempt)
            #endif

        // Several visible rows can enqueue pagination before the first request fails.
        // Recheck when each task actually executes so a queued request cannot silently
        // consume the error and bypass the reader's explicit inline retry.
        guard !automatic || error == nil else {
            #if DEBUG
            RefreshDiagnostics.shared.record(.skippedError)
            #endif
            return
        }
        guard !loading || requestContext != context else {
            #if DEBUG
            RefreshDiagnostics.shared.record(.skippedBusy)
            #endif
            return
        }
        guard !older || hasMore else {
            #if DEBUG
            RefreshDiagnostics.shared.record(.skippedEnd)
            #endif
            return
        }
        let attempt = UUID(), currentContext = context, selected = preferences
        requestID = attempt; requestContext = currentContext; loading = true
        defer { if requestID == attempt { loading = false } }
        var fields = selected.parameters; fields["limit"] = .number(20)
        if older, let id = feed.olderCursor { fields["untilId"] = .string(id) }
        do {

            #if DEBUG
            RefreshDiagnostics.shared.record(.requestStarted)
            #endif
            let result = Record.list(try await session.call("notes/\(selected.selected)-timeline", fields))

            #if DEBUG
            RefreshDiagnostics.shared.record(.requestReturned)
            #endif
            try Task.checkCancellation(); guard requestID == attempt, context == currentContext else { return }
            if older || atTop || feed.notes.isEmpty {
            #if DEBUG
            RefreshDiagnostics.shared.record(.rowsApplied)
            #endif
                feed.page(result, older: older, preferences: selected, accountID: session.user?.id) }
            else {
            #if DEBUG
            RefreshDiagnostics.shared.record(.rowsPending)
            #endif
                for note in result { feed.receive(note, atTop: false, preferences: selected, accountID: session.user?.id) } }
            if older || !firstPageLoaded { hasMore = result.count == 20 }
            if !older { firstPageLoaded = true }
            error = nil; failedOlderRequest = false; cached = false; firstLoadFinished = true
            if let owner = session.user?.id { try? session.store?.save(TimelineCache(savedAt: Date(), notes: Array(feed.notes.filter { $0["visibility"].string == "public" }.prefix(100))), account: "public-" + owner, key: "timeline-" + selected.requestKey) }
        } catch is CancellationError {} catch {
            #if DEBUG
            RefreshDiagnostics.shared.record(.loadFailed)
            #endif

            guard requestID == attempt, context == currentContext else { return }
            if (error as? APIError)?.code == "LTL_DISABLED" { session.timelinePreferences.selected = "home"; session.timelineNotice = "本地时间线暂不可用，已切换到关注。" }
            else { failedOlderRequest = older; self.error = error.localizedDescription; firstLoadFinished = true }
        }
    }
}

struct NoteCard: View {
    @Environment(\.openNoteCard) private var navigate
    @Environment(AppSession.self) private var session
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .subheadline) private var nameSize = 12.6
    @ScaledMetric(relativeTo: .caption) private var accountSize = 12.6
    @ScaledMetric(relativeTo: .caption2) private var timeSize = 11.34
    let note: Record
    var detail = false
    var timelineStyle = false
    var hideSensitive = false
    var appearance: NoteAppearance = .standard
    @ScaledMetric(relativeTo: .subheadline) private var actionSize = 16.3
    @ScaledMetric(relativeTo: .subheadline) private var actionCountSize = 12.6
    @State private var revealCW = false
    @State private var revealSensitivePost = false
    @State private var confirmReaction = false
    @State private var proposedReaction: String?
    @State private var pendingReactionConfirmation = false
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
    private var rowID: String { appearance.isTimeline ? note.id : shown.id }
    private var ownDeleteID: String? { note.user.id == session.user?.id ? note.id : shown.user.id == session.user?.id ? shown.id : nil }
    var body: some View { if !session.deletedNoteIDs.contains(note.id) && !session.deletedNoteIDs.contains(shown.id) { content } }
    private var content: some View {
        VStack(alignment: .leading, spacing: appearance.isTimeline ? 4 : 6) {
            if NoteContext.isRepost(note) {
                Button { navigate(.author(note.user.id)) } label: { Label { Text(note.user.displayName + " 转发了") } icon: { NoteIcon(system: "arrow.2.squarepath", web: "repeat", appearance: appearance) }.font(.caption).frame(minHeight: appearance.isTimeline ? 44 : 28) }.buttonStyle(.plain).foregroundStyle(PUBOTheme.secondary)
            }
            if !shown["replyId"].isNull || !shown["reply"]["id"].isNull {
                NoteContextCard(value: shown["reply"], targetID: shown["replyId"].string, label: "回复", appearance: appearance)
            }
            HStack(alignment: .top, spacing: 10) {
                Button { navigate(.author(shown.user.id)) } label: { Avatar(user: shown.user, size: 46).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityLabel(shown.user.displayName + "的头像").padding(.top, appearance.isTimeline ? 12 : 0)
                VStack(alignment: .leading, spacing: appearance.isTimeline ? 0 : 4) {
                    authorHeader
                    if hideSensitive && TimelinePresentation.sensitive(shown) && !revealSensitivePost {
                        Button { revealSensitivePost = true } label: {
                            Text("已折叠含敏感媒体的帖子 · 展开").font(.caption)
                                .frame(minHeight: 44).feedHitShape(appearance)
                        }
                    } else {
                        if let cw = shown["cw"].string {
                            Button { revealCW.toggle() } label: { Label { Text(cw.isEmpty ? "内容警告 · 点击展开" : cw) } icon: { NoteIcon(system: revealCW ? "eye.slash" : "eye", web: revealCW ? "eye-off" : "eye", appearance: appearance) }.frame(minHeight: 44) }.buttonStyle(.plain).accessibilityValue(revealCW ? "已展开" : "已隐藏")
                        }
                        if shown["cw"].isNull || revealCW {
                            NoteText(text: shown.text, remoteEmojis: shown["emojis"], onTap: detail ? nil : { navigate(.note(shown.id)) }, identifier: "note.open." + shown.id, appearance: appearance)
                            PublicMediaGrid(files: Record.list(shown["files"]), noteID: shown.id)
                            if !shown["poll"].isNull { PollView(noteID: shown.id, initial: shown["poll"]).id(shown.id).disabled(session.user == nil) }
                            if !shown["renoteId"].isNull || !shown["renote"]["id"].isNull { NoteContextCard(value: shown["renote"], targetID: shown["renoteId"].string, label: "引用", appearance: appearance) }
                            NoteLinkPreviews(text: shown.text, active: true, appearance: appearance)
                            if shown.text.contains("$[") {
                                Link(destination: Endpoint.origin.appendingPathComponent("notes/" + shown.id)) {
                                    Text("在网页查看完整内容").font(.caption).feedHeaderTarget(appearance, alignment: .leading)
                                }
                            }
                        }
                        reactions
                    }
                    actions
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.font(.system(size: 14)).padding(.horizontal, 16)
            .padding(.top, appearance.isTimeline ? 2 : 14)
            .padding(.bottom, appearance.isTimeline ? 3 : 14)
            .background(PUBOTheme.panel).overlay(alignment: .bottom) { Rectangle().fill(PUBOTheme.divider).frame(height: 0.5) }
            .listRowInsets(EdgeInsets()).listRowSeparator(.hidden).listRowBackground(Color.clear)
            .contextMenu { Link("在本站网页打开原帖", destination: Endpoint.origin.appendingPathComponent("notes/" + shown.id)) }
            .onChange(of: note) { _, _ in current = nil }
            .onAppear { if !timelineStyle { session.stream.captureNotes(TimelinePresentation.capturedIDs([note]), owner: captureOwner) } }
            .onDisappear { if !timelineStyle { session.stream.captureNotes([], owner: captureOwner) }; revealSensitivePost = false }
            .onChange(of: hideSensitive) { _, _ in revealSensitivePost = false }
            .onReceive(session.noteEvents) { event in
                guard !timelineStyle else { return }
                current = event.applying(to: current ?? note, accountID: session.user?.id)
                if event.kind == "deleted" { session.deletedNoteIDs.insert(event.id) }
            }
            .confirmationDialog(proposedReaction == nil ? "取消这个表情反应？" : "更换表情反应？", isPresented: $confirmReaction) {
                Button(proposedReaction == nil ? "取消反应" : "更换反应") { Task { await react(proposedReaction) } }
                    .accessibilityIdentifier("note.confirmReaction." + shown.id)
            }
            .sheet(isPresented: $reactionPicker, onDismiss: { if pendingReactionConfirmation { pendingReactionConfirmation = false; confirmReaction = true } }) { ReactionPicker { reaction in
                let previous = shown["myReaction"].string
                proposedReaction = previous == reaction ? nil : reaction
                if previous != nil { pendingReactionConfirmation = true } else { Task { await react(reaction) } }
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
        let stacked = appearance.isTimeline && typeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0)) :
            AnyLayout(HStackLayout(alignment: appearance.isTimeline ? .center : .firstTextBaseline, spacing: 4))
        return layout {
            Button { navigate(.author(shown.user.id)) } label: {
                HStack(spacing: appearance.isTimeline ? 6.3 : 3) {
                    Text(shown.user.displayName).font(.system(size: nameSize, weight: .bold)).lineLimit(1).layoutPriority(appearance.isTimeline ? 2 : 0)
                    if shown.user["isBot"].bool { Text("bot").font(.system(size: 9)).padding(.horizontal, 2).overlay(RoundedRectangle(cornerRadius: 2).stroke(PUBOTheme.divider)) }
                    Text("@" + (shown.user["username"].string ?? "")).font(.system(size: accountSize)).foregroundStyle(appearance.isTimeline ? PUBOTheme.text : PUBOTheme.secondary).lineLimit(1).layoutPriority(appearance.isTimeline ? -1 : 0)
                    UserInlineBadges(user: shown.user, appearance: appearance).fixedSize(horizontal: appearance.isTimeline, vertical: appearance.isTimeline)
                }.feedHeaderTarget(appearance, alignment: .leading, fullWidth: stacked)
            }.buttonStyle(.plain).accessibilityIdentifier("note.author." + rowID)
            if !stacked { Spacer(minLength: 0) }
            Button { navigate(.note(shown.id)) } label: {
                HStack(spacing: 3) {
                    if let date = puboDate(shown["createdAt"].string) { Group { if appearance.isTimeline { ChatRelativeTime(date: date) } else { Text(date, style: .relative) } }.lineLimit(1) }
                    if shown["visibility"].string != "public" { NoteIcon(system: TimelinePresentation.visibilityIcon(shown["visibility"].string), web: shown["visibility"].string == "home" ? "home" : shown["visibility"].string == "specified" ? "mail" : "lock", appearance: appearance, size: timeSize * 1.29) }
                    if shown["localOnly"].bool { NoteIcon(system: "network.slash", web: "rocket-off", appearance: appearance, size: timeSize * 1.29).accessibilityLabel("仅本站") }
                }.font(.system(size: timeSize)).foregroundStyle(PUBOTheme.secondary)
                    .feedHeaderTarget(appearance, alignment: .trailing, fullWidth: stacked)
            }.buttonStyle(.plain).fixedSize(horizontal: appearance.isTimeline && !stacked, vertical: false).layoutPriority(appearance.isTimeline ? 3 : 0).accessibilityLabel("查看帖子时间和详情，" + TimelinePresentation.visibilityLabel(shown["visibility"].string) + (shown["localOnly"].bool ? "，仅本站" : "")).accessibilityIdentifier("note.timestamp." + rowID)
        }.frame(minHeight: 18)
    }
    private var actionLayout: AnyLayout { appearance.isTimeline ? AnyLayout(FeedActionsLayout(spacing: typeSize.isAccessibilitySize ? 8 : 24.5)) : AnyLayout(HStackLayout(spacing: 12)) }
    private var actions: some View {
        Group {
            if session.user != nil { actionLayout {
                Button { replying = true } label: { HStack(spacing: 4) { NoteIcon(system: "arrowshape.turn.up.left", web: "arrow-back-up", appearance: appearance, size: actionSize); if shown["repliesCount"].int > 0 { Text("\(shown["repliesCount"].int)").font(appearance.isTimeline ? .system(size: actionCountSize) : .caption) } }.frame(minWidth: 44, minHeight: 44).feedHitShape(appearance) }.accessibilityLabel("回复").accessibilityIdentifier("note.reply." + rowID)
                Menu {
                    Button("转发") { Task { await renote() } }
                    Button("引用转发") { quoting = true }
                } label: { HStack(spacing: 3) { NoteIcon(system: "arrow.2.squarepath", web: "repeat", appearance: appearance, size: actionSize); if shown["renoteCount"].int > 0 { Text("\(shown["renoteCount"].int)").font(appearance.isTimeline ? .system(size: actionCountSize) : .caption2) } }.frame(minWidth: 44, minHeight: 44).feedHitShape(appearance) }
                .accessibilityLabel("转发或引用").accessibilityIdentifier("note.renote." + rowID)
                Button {
                    if !shown["myReaction"].isNull { proposedReaction = nil; confirmReaction = true }
                    else if shown["reactionAcceptance"].string == "likeOnly" { Task { await react("❤️") } }
                    else { reactionPicker = true }
                } label: {
                    HStack(spacing: 3) {
                        NoteIcon(system: shown["reactionAcceptance"].string == "likeOnly" ? (shown["myReaction"].isNull ? "heart" : "heart.fill") : (shown["myReaction"].isNull ? "plus" : "minus"), web: shown["reactionAcceptance"].string == "likeOnly" ? (shown["myReaction"].isNull ? "heart" : "heart-filled") : (shown["myReaction"].isNull ? "plus" : "minus"), appearance: appearance, size: actionSize)
                        if shown["reactionAcceptance"].string == "likeOnly", shown["reactionCount"].int > 0 { Text("\(shown["reactionCount"].int)").font(appearance.isTimeline ? .system(size: actionCountSize) : .caption2) }
                    }.frame(minWidth: 44, minHeight: 44).feedHitShape(appearance).foregroundStyle(shown["myReaction"].isNull ? (appearance.isTimeline ? FeedColors.action : PUBOTheme.secondary) : PUBOTheme.accent)
                }.accessibilityLabel(shown["myReaction"].isNull ? "添加表情反应" : "取消反应").accessibilityIdentifier("note.addReaction." + rowID)
                if !appearance.isTimeline { Spacer(minLength: 0) }
                Menu {
                    Button("收藏帖子") { Task { await favorite(true) } }.accessibilityIdentifier("note.favorite." + shown.id)
                    Button("取消收藏") { Task { await favorite(false) } }
                    Button("加入剪藏") { selectingClip = true }
                    Button("查看反应详情") { viewingReactions = true }
                    if ownDeleteID != nil { Button("删除帖子", role: .destructive) { confirmDelete = true } }
                    if let id = ownDeleteID { Button((session.user?["pinnedNoteIds"].array.compactMap(\.string) ?? []).contains(id) ? "取消置顶帖子" : "置顶到个人主页") { Task { await pin(id) } } }
                    if shown.user.id != session.user?.id { Button("举报帖子") { reporting = true }; Button("屏蔽作者", role: .destructive) { confirmBlock = true } }
                    Link("在网页打开原帖", destination: Endpoint.origin.appendingPathComponent("notes/" + shown.id))
                } label: { NoteIcon(system: "ellipsis", web: "dots", appearance: appearance, size: actionSize).frame(width: 44, height: 44).feedHitShape(appearance) }.accessibilityLabel("帖子更多操作").accessibilityIdentifier("note.more." + rowID)
            }.buttonStyle(.borderless).foregroundStyle(appearance.isTimeline ? FeedColors.action : PUBOTheme.secondary).disabled(busy)
            } else { Text("登录后可回复、转发或添加反应").font(.caption).foregroundStyle(.secondary) }

        }.font(.system(size: appearance.isTimeline ? actionSize : 15))
    }
    private var reactions: some View {
        NoteReactionStrip(note: shown, disabled: busy || session.user == nil,
            pulse: reactionPulse, choose: chooseReaction,
            more: { viewingReactions = true }, appearance: appearance)
            .padding(.top, appearance.isTimeline && !shown["reactions"].object.isEmpty ? 6 : 0)
    }
    private func chooseReaction(_ reaction: String) {
        let previous = shown["myReaction"].string
        if previous != nil {
            proposedReaction = previous == reaction ? nil : reaction
            confirmReaction = true
        } else { Task { await react(reaction) } }
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

