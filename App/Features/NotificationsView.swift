import SwiftUI
import PUBOCore

struct NotificationsView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.timelineWindowTypeSize) private var typeSize
    @State private var tab = NotificationTab.all
    @State private var filter: NotificationKind?
    @State private var items: [Record] = []
    @State private var queued: [Record] = []
    @State private var receivedDuringRequest: [Record] = []
    @State private var cursor: String?
    @State private var more = false
    @State private var loading = false
    @State private var pull = NotificationPullProgress()
    @State private var refreshState = NotificationRefreshState()
    @State private var errorMessage: String?
    @State private var retryOlder = false
    @State private var actionMessage: String?
    @State private var markingRead = false
    @State private var readConfirmation: UUID?
    @State private var requestStates: [String: String] = [:]
    @State private var requestID = UUID()
    @State private var visible = false
    @State private var atTop = true
    @State private var showRequests = false
    @State private var options: [NotificationTab: NoteListOptions] = [:]
    @State private var scrolledList = false
    @State private var autoCursor: String?
    @ScaledMetric(relativeTo: .caption) private var tabSize = 11.2

    private var active: Bool { visible && session.selectedTab == 1 && phase == .active }
    private var noteOptions: NoteListOptions { options[tab] ?? NoteListOptions() }
    private var query: String {
        if tab == .all { return "all/" + (filter?.rawValue ?? "*") }
        return "\(tab.rawValue)/\(noteOptions.oldestFirst)/\(noteOptions.date?.timeIntervalSince1970 ?? 0)"
    }
    private var enterAnimation: Animation? { reduced ? nil : .timingCurve(0.23, 1, 0.32, 1, duration: 0.7) }
    private var tabItems: [ChatTab] { [
        .init(id: "all", title: "全部", icon: "circle"),
        .init(id: "mentions", title: "提到我的", icon: "at"),
        .init(id: "directNotes", title: "私信", icon: "envelope")
    ] }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                feed.id(query)
            }
            .puboScreen().navigationTitle("通知").toolbar(.hidden, for: .navigationBar)
            .overlay {
                if active && tab == .all && (markingRead || readConfirmation != nil) {
                    Group {
                        if readConfirmation != nil {
                            Image(systemName: "checkmark").font(.system(size: 32, weight: .semibold))
                                .foregroundStyle(PUBOTheme.accent).accessibilityLabel("全部通知已读")
                        } else { ProgressView().accessibilityLabel("正在标记已读") }
                    }.frame(width: 96, height: 96)
                        .background(PUBOTheme.panel, in: RoundedRectangle(cornerRadius: PUBOTheme.radius))
                        .shadow(color: .black.opacity(0.14), radius: 8).allowsHitTesting(false)
                }
            }
            .task(id: readConfirmation) {
                guard let confirmation = readConfirmation else { return }
                try? await Task.sleep(for: .seconds(1))
                if !Task.isCancelled && readConfirmation == confirmation { readConfirmation = nil }
            }
            .environment(\.dynamicTypeSize, typeSize)
            .navigationDestination(isPresented: $showRequests) { FollowRequestsView() }
            .onAppear { visible = true }
            .onDisappear { visible = false; readConfirmation = nil; invalidateRequest() }
            .task(id: query + (active ? "/visible" : "/hidden")) {
                guard active else { invalidateRequest(); return }
                if refreshState.loadedQuery != query {
                    invalidateRequest()
                    refreshState.clearDisplayedQuery()
                    items = []; queued = []; cursor = nil; more = false; errorMessage = nil; atTop = true
                    scrolledList = false; autoCursor = nil
                    await load()
                } else if refreshState.shouldRefresh(query, atTop: atTop) || (atTop && tab == .all && session.badges.notification) {
                    await load(keepTail: true)
                }
            }
            .onChange(of: session.connectionRevision) { old, _ in
                guard old > 0 else { return }
                refreshState.invalidate()
                if active && atTop { Task { await load(keepTail: true) } }
            }
            .onReceive(session.notificationEvents, perform: receive)
            .onReceive(session.notificationFlushes) { _ in
                refreshState.invalidate()
                if active && tab == .all {
                    invalidateRequest()
                    queued = []
                    Task { await load() }
                }
            }
            .alert("通知", isPresented: Binding(get: { actionMessage != nil }, set: { if !$0 { actionMessage = nil } })) {
                Button("好") { actionMessage = nil }
            } message: { Text(actionMessage ?? "") }
        }
    }
    private var header: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .trailing) {
                Label("通知", systemImage: "bell").font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity).accessibilityAddTraits(.isHeader)
                if tab == .all {
                    HStack(spacing: 0) {
                        headerFilter
                        Button { Task { await markRead() } } label: { headerIcon("checkmark") }
                            .disabled(markingRead).accessibilityLabel("全部标记为已读").accessibilityIdentifier("notifications.markRead")
                    }.padding(.trailing, 8)
                }
            }.frame(minHeight: 50)
            ViewThatFits(in: .horizontal) {
                tabs
                ScrollView(.horizontal) { tabs }.scrollIndicators(.hidden)
            }
        }.background(PUBOTheme.background)
            .overlay(alignment: .bottom) { Rectangle().fill(PUBOTheme.divider).frame(height: 0.5) }
    }
    private var tabs: some View {
        HStack(spacing: 0) {
            ForEach(tabItems) { option in
                Button { if let value = NotificationTab(rawValue: option.id) { tab = value } } label: {
                    Label(option.title, systemImage: option.icon).labelStyle(.titleAndIcon)
                        .font(.system(size: tabSize, weight: option.id == tab.rawValue ? .semibold : .regular))
                        .fixedSize().padding(.horizontal, 12).frame(minHeight: 44)
                        .overlay(alignment: .bottom) {
                            Capsule().fill(option.id == tab.rawValue ? PUBOTheme.accent : .clear).frame(height: 3)
                        }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(option.title).accessibilityIdentifier("notifications.tab." + option.id)
                    .accessibilityAddTraits(option.id == tab.rawValue ? .isSelected : [])
            }
        }
    }
    private var headerFilter: some View {
                Menu {
                    if filter != nil {
                        Button { filter = nil } label: { Label("清除", systemImage: "xmark") }
                            .accessibilityIdentifier("notifications.filter.clear")
                        Divider()
                    }
                    ForEach(NotificationKind.allCases, id: \.self) { type in
                        Button { filter = type } label: {
                            if filter == type { Label(type.title, systemImage: "checkmark") }
                            else { Text(type.title) }
                        }.accessibilityIdentifier("notifications.filter." + type.rawValue)
                    }
                    Divider()
                    Button("关注申请") { showRequests = true }
                } label: { headerIcon("line.3.horizontal.decrease") }
                    .foregroundStyle(filter == nil ? PUBOTheme.text : PUBOTheme.accent)
                    .accessibilityLabel("筛选").accessibilityValue(filter?.title ?? "全部")
                    .accessibilityIdentifier("notifications.filter")
    }
    private func headerIcon(_ system: String) -> some View {
        Image(systemName: system).font(.system(size: 15)).frame(width: 44, height: 44).contentShape(Rectangle())
    }
    private var noteControls: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Menu {
                    Button("从新到旧") { options[tab, default: .init()].oldestFirst = false }
                    Button("从旧到新") { options[tab, default: .init()].oldestFirst = true }
                } label: {
                    HStack { Image(systemName: "arrow.up.arrow.down"); Text(noteOptions.oldestFirst ? "从旧到新" : "从新到旧"); Spacer(); Image(systemName: "chevron.down") }
                        .padding(.horizontal, 12).frame(minHeight: 44)
                        .background(PUBOTheme.panel, in: RoundedRectangle(cornerRadius: 8))
                }.accessibilityIdentifier("notifications.order")
                Button {
                    options[tab, default: .init()].date = noteOptions.date == nil ? Date() : nil
                } label: { headerIcon("calendar") }.accessibilityLabel("日期").accessibilityIdentifier("notifications.date")
                    .foregroundStyle(noteOptions.date == nil ? PUBOTheme.text : PUBOTheme.accent)
                Button { Task { await load() } } label: { headerIcon("arrow.clockwise") }
                    .accessibilityLabel("刷新").accessibilityIdentifier("notifications.refresh")
            }.font(.caption).buttonStyle(.plain)
            if let date = noteOptions.date {
                DatePicker("日期", selection: Binding(get: { date }, set: { options[tab, default: .init()].date = Calendar.current.startOfDay(for: $0) }), displayedComponents: .date)
                    .datePickerStyle(.compact)
            }
        }.padding(.bottom, 8)
    }
    private var feed: some View {
        let displayed = items
        return ScrollView {
            LazyVStack(spacing: tab == .all ? 0 : 8) {
                Color.clear.frame(height: 1).background(GeometryReader { g in
                    Color.clear.preference(key: NotificationScrollTop.self, value: g.frame(in: .named("notification-scroll")).minY)
                })
                if tab != .all { noteControls }
                if let errorMessage { ErrorBanner(message: errorMessage) { Task { await load(older: retryOlder) } } }
                ForEach(Array(displayed.enumerated()), id: \.element.id) { index, item in
                    VStack(spacing: 0) {
                        if index > 0 { dateBoundary(displayed[index - 1], item) }
                        row(item)
                        Rectangle().fill(PUBOTheme.divider).frame(height: 0.5)
                    }
                    .background(PUBOTheme.panel)
                    .clipShape(RoundedRectangle(cornerRadius: tab == .all ? 0 : PUBOTheme.radius))
                    .transition(.asymmetric(insertion: reduced ? .identity : .offset(y: -64).combined(with: .opacity),
                                            removal: reduced ? .identity : .opacity.animation(.easeOut(duration: 0.2))))
                }
                if more && !items.isEmpty {
                    Button { Task { await load(older: true) } } label: {
                        Group { if loading { ProgressView() } else { Text("加载更多").font(.subheadline) } }
                            .frame(maxWidth: .infinity, minHeight: 48).contentShape(Rectangle())
                    }.disabled(loading).buttonStyle(.plain).accessibilityIdentifier("notifications.more")
                        .onAppear { loadVisibleOlder() }
                } else if loading && items.isEmpty {
                    ProgressView("加载中…").padding(24)
                } else if items.isEmpty && errorMessage == nil {
                    Text(tab == .all ? "暂无通知" : "暂无帖子").font(.subheadline).foregroundStyle(.secondary).padding(28)
                }
            }.background(tab == .all ? PUBOTheme.panel : PUBOTheme.background).clipShape(RoundedRectangle(cornerRadius: PUBOTheme.radius))
                .padding(12)
                .background(alignment: .topLeading) {
                    NotificationPullObserver(progress: pull, active: active, refresh: refreshFromUser)
                        .frame(width: 0, height: 0)
                }
        }.coordinateSpace(name: "notification-scroll")
            .modifier(NotificationPullPresentation(progress: pull))
            .onPreferenceChange(NotificationScrollTop.self) { top in
                // The lazy stack removes the marker offscreen. Its absent value means history is visible.
                let wasAtTop = atTop
                atTop = top.map { $0 >= -2 } ?? false
                if atTop {
                    releaseQueue()
                    if !wasAtTop && active && refreshState.shouldRefresh(query, atTop: true) {
                        Task { await load(keepTail: true) }
                    }
                }
            }
            .simultaneousGesture(DragGesture(minimumDistance: 34).onChanged { drag in
                if abs(drag.translation.height) > abs(drag.translation.width) { scrolledList = true }
            }.onEnded { drag in
                let x = drag.translation.width, y = drag.translation.height
                guard abs(x) > 80, abs(x) > abs(y) * 2, let index = NotificationTab.allCases.firstIndex(of: tab) else { return }
                let next = index + (x < 0 ? 1 : -1)
                if NotificationTab.allCases.indices.contains(next) { tab = NotificationTab.allCases[next] }
            })
    }
    @ViewBuilder private func row(_ item: Record) -> some View {
        if tab != .all { NoteCard(note: item, appearance: .timeline) }
        else if ["mention", "reply", "quote"].contains(item["type"].string ?? ""), !item["note"]["id"].isNull {
            NoteCard(note: Record(item["note"]), appearance: .timeline)
        } else {
            NotificationRow(item: item, requestState: requestStates[item.id]) { accept in
                Task { await respond(item, accept: accept) }
            }
        }
    }
    @ViewBuilder private func dateBoundary(_ previous: Record, _ next: Record) -> some View {
        if let a = puboDate(previous["createdAt"].string), let b = puboDate(next["createdAt"].string),
           !Calendar.current.isDate(a, inSameDayAs: b) {
            HStack(spacing: 12) {
                Text("⌃ " + dateText(a))
                Rectangle().fill(PUBOTheme.divider).frame(width: 1, height: 12)
                Text(dateText(b) + " ⌄")
            }.font(.caption).foregroundStyle(PUBOTheme.secondary).padding(8)
            Rectangle().fill(PUBOTheme.divider).frame(height: 0.5)
        }
    }
    private func dateText(_ date: Date) -> String {
        "\(Calendar.current.component(.month, from: date))/\(Calendar.current.component(.day, from: date))"
    }
    private func invalidateRequest() {
        if loading { refreshState.invalidate() }
        requestID = UUID(); loading = false; receivedDuringRequest = []
    }
    private func loadVisibleOlder() {
        guard active, scrolledList, more, !loading, errorMessage == nil, let cursor, autoCursor != cursor else { return }
        autoCursor = cursor
        Task { await load(older: true) }
    }
    private func receive(_ item: Record) {
        guard !item.id.isEmpty else { return }
        guard active else { refreshState.invalidate(); return }
        guard tab == .all else { return }
        session.stream.readVisibleNotifications()
        guard filter == nil || NotificationKind(record: item) == filter else { return }
        if loading { receivedDuringRequest.insert(item, at: 0) }
        guard !items.contains(where: { $0.id == item.id }), !queued.contains(where: { $0.id == item.id }) else { return }
        queued.insert(item, at: 0)
        if atTop { releaseQueue() }
    }
    private func releaseQueue() {
        guard active, !queued.isEmpty else { return }
        let newItems = joined(queued, items)
        queued = []
        withAnimation(enterAnimation) { items = newItems }
    }
    private func joined(_ first: [Record], _ second: [Record]) -> [Record] {
        var seen = Set<String>()
        return (first + second).filter { seen.insert($0.id).inserted }
    }
    private func load(older: Bool = false, keepTail: Bool = false) async {
        guard active, !loading, !older || (more && cursor != nil) else { return }
        let current = UUID(), key = query, source = tab, requestFilter = filter
        let oldCursor = older ? cursor : nil
        let revision = refreshState.revision
        requestID = current; loading = true; receivedDuringRequest = []
        defer {
            if requestID == current {
                loading = false; receivedDuringRequest = []
                if !Task.isCancelled && active && errorMessage == nil && key == query && refreshState.shouldRefresh(key, atTop: atTop) {
                    Task { await load(keepTail: true) }
                }
            }
        }
        do {
            let value = try await session.call(source.endpoint, source.parameters(filter: requestFilter, until: oldCursor,
                                                   oldestFirst: noteOptions.oldestFirst, date: noteOptions.date))
            try Task.checkCancellation()
            guard requestID == current, active, key == query else { return }
            guard case .array = value else { throw APIError.invalidResponse }
            let page = Record.list(value)
            if older {
                items = joined(items, page)
            } else {
                var next = joined(receivedDuringRequest, page)
                if keepTail, let last = page.last?.id, let overlap = items.firstIndex(where: { $0.id == last }) {
                    next = joined(next, Array(items.dropFirst(overlap + 1)))
                }
                if refreshState.loadedQuery == key && !items.isEmpty && !keepTail {
                    withAnimation(enterAnimation) { items = next }
                } else { items = next }
                queued = []
            }
            // A retained older tail owns its own cursor.
            if !keepTail || items.last?.id == page.last?.id {
                cursor = page.last?.id
                more = source.canLoadOlder(page, previousCursor: oldCursor)
            }
            if !older { refreshState.didLoad(key, revision: revision) }
            errorMessage = nil
            if source == .all && !page.isEmpty { await session.refreshUnread() }
        } catch {
            if requestID == current && active && key == query && !Task.isCancelled {
                errorMessage = error.localizedDescription
                retryOlder = older
            }
        }
    }
    private func refreshFromUser() async {
        guard active else { return }
        // Supersede pagination or badge reconciliation that was already in flight.
        if loading { invalidateRequest() }
        await load()
    }
    private func markRead() async {
        guard !markingRead else { return }
        markingRead = true
        readConfirmation = nil
        defer { markingRead = false }
        do {
            _ = try await session.call("notifications/mark-all-as-read", mutation: true)
            if active && tab == .all { readConfirmation = UUID() }
            Task { await session.refreshUnread() }
        } catch { if !Task.isCancelled { actionMessage = error.localizedDescription } }
    }
    private func respond(_ item: Record, accept: Bool) async {
        guard requestStates[item.id] == nil, !item.user.id.isEmpty else { return }
        requestStates[item.id] = "处理中…"
        do {
            _ = try await session.call(accept ? "following/requests/accept" : "following/requests/reject", ["userId": .string(item.user.id)], mutation: true)
            requestStates[item.id] = accept ? "已接受" : "已拒绝"
        } catch {
            if (error as? APIError) == .uncertain {
                requestStates[item.id] = "结果待核对，请打开关注申请查看。"
            } else { requestStates[item.id] = nil }
            actionMessage = error.localizedDescription
        }
    }
}

private struct NotificationScrollTop: PreferenceKey {
    static var defaultValue: CGFloat? { nil }
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) { value = nextValue() ?? value }
}

private struct NoteListOptions {
    var oldestFirst = false
    var date: Date?
}

@MainActor @Observable
private final class NotificationPullProgress {
    enum Phase { case idle, pulling, armed, refreshing }
    static let threshold: CGFloat = 200
    var phase = Phase.idle
    var height: CGFloat = 0

    func move(_ distance: CGFloat) {
        phase = distance >= Self.threshold ? .armed : .pulling
        // Match the resistance curve of the website's drag indicator.
        height = (distance / (1.5 + distance / 170)).rounded()
    }
    func beginRefresh() {
        move(Self.threshold)
        phase = .refreshing
    }
    func reset() {
        phase = .idle
        height = 0
    }
}

private struct NotificationPullPresentation: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduced
    let progress: NotificationPullProgress

    func body(content: Content) -> some View {
        let phase = progress.phase
        let refreshing = phase == .refreshing
        let label = refreshing ? "刷新中" : phase == .armed ? "松开以刷新" : "下拉刷新"
        content
            .padding(.top, refreshing ? progress.height : 0)
            .overlay(alignment: .top) {
                if phase != .idle {
                    VStack(spacing: 4) {
                        if refreshing && !reduced {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: refreshing ? "arrow.clockwise" : "arrow.down.to.line")
                                .rotationEffect(.degrees(phase == .armed && !reduced ? 180 : 0))
                                .animation(reduced ? nil : .easeOut(duration: 0.25), value: phase == .armed)
                        }
                        Text(label).font(.footnote)
                    }
                    .foregroundStyle(PUBOTheme.secondary)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity)
                    .frame(height: progress.height, alignment: .bottom)
                    .clipped().background(PUBOTheme.background)
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .ignore).accessibilityLabel(label)
                    .accessibilityIdentifier("notifications.pull.status")
                    .transition(.opacity)
                }
            }
            .animation(reduced ? nil : .easeOut(duration: 0.2), value: refreshing)
            .animation(reduced ? nil : .easeOut(duration: 0.2), value: phase == .idle)
    }
}

/// Observe the existing scroll pan without installing a competing recognizer or changing its delegate.
private struct NotificationPullObserver: UIViewRepresentable {
    let progress: NotificationPullProgress
    let active: Bool
    let refresh: @MainActor () async -> Void

    func makeUIView(context: Context) -> Anchor { Anchor() }
    func updateUIView(_ view: Anchor, context: Context) {
        view.progress = progress
        view.refresh = active ? refresh : nil
        if !active { view.cancel() }
        view.attach()
    }
    static func dismantleUIView(_ view: Anchor, coordinator: ()) { view.detach() }

    final class Anchor: UIView {
        weak var progress: NotificationPullProgress?
        var refresh: (@MainActor () async -> Void)?
        private weak var scroll: UIScrollView?
        private var previousBounce = false
        private var tracking = false
        private var worker: Task<Void, Never>?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            accessibilityElementsHidden = true
        }
        required init?(coder: NSCoder) { nil }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { detach() } else { attach() }
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            attach()
        }
        func attach() {
            guard window != nil else { return }
            var ancestor = superview
            while let view = ancestor {
                if let container = view as? UIScrollView {
                    if container !== scroll {
                        detach()
                        scroll = container
                        previousBounce = container.alwaysBounceVertical
                        container.alwaysBounceVertical = true
                        container.panGestureRecognizer.addTarget(self, action: #selector(panChanged(_:)))
                    }
                    return
                }
                ancestor = view.superview
            }
        }
        func cancel() {
            if tracking || worker != nil { progress?.reset() }
            tracking = false
            worker?.cancel()
            worker = nil
        }
        func detach() {
            cancel()
            scroll?.panGestureRecognizer.removeTarget(self, action: #selector(panChanged(_:)))
            scroll?.alwaysBounceVertical = previousBounce
            scroll = nil
        }
        @objc private func panChanged(_ pan: UIPanGestureRecognizer) {
            guard let scroll, let progress, let refresh, worker == nil else { return }
            let delta = pan.translation(in: window)
            switch pan.state {
            case .began:
                tracking = scroll.contentOffset.y + scroll.adjustedContentInset.top <= 2
            case .changed:
                guard tracking else { return }
                guard delta.y > 0, delta.y > abs(delta.x) else {
                    progress.reset()
                    return
                }
                progress.move(delta.y)
            case .ended:
                guard tracking else { return }
                tracking = false
                guard delta.y >= NotificationPullProgress.threshold, delta.y > abs(delta.x) else {
                    progress.reset()
                    return
                }
                progress.beginRefresh()
                worker = Task { @MainActor [weak self] in
                    await refresh()
                    guard !Task.isCancelled else { return }
                    progress.reset()
                    self?.worker = nil
                }
            case .cancelled, .failed:
                if tracking { progress.reset() }
                tracking = false
            default: break
            }
        }
    }
}
