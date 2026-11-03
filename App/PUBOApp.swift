import SwiftUI

@main
struct PUBOApp: App {
    @UIApplicationDelegateAdaptor(NativeAppDelegate.self) private var appDelegate
    @State private var session = AppSession()
    @State private var profileTabAvatar: UIImage?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var systemTypeSize
    var body: some Scene {
        WindowGroup {
            Group {
                if session.restoring { AppLaunchSkeleton() }
                else if session.user == nil { AuthView() }
                else {
                    TabView(selection: $session.selectedTab) {
                        TimelineView().tabItem { Label("动态", systemImage: "house") }.tag(0)
                        NotificationsView().tabItem { Label("通知", systemImage: "bell") }.badge(session.badges.notificationLabel).tag(1)
                        ChatListView().tabItem { Label("私信", systemImage: "bubble.left.and.bubble.right") }.badge(session.badges.chatLabel).tag(2)
                        MyAccountView().tabItem {
                            if let profileTabAvatar { Image(uiImage: profileTabAvatar).renderingMode(.original); Text("我的") }
                            else { Label("我的", systemImage: "person.crop.circle") }
                        }.tag(3)
                    }.id(session.generation).toolbarBackground(PUBOTheme.panel, for: .tabBar).toolbarBackground(.visible, for: .tabBar)
                }
            }.environment(session).tint(PUBOTheme.accent).foregroundStyle(PUBOTheme.text)
                .environment(\.locale, Locale(identifier: "zh_CN"))
                .environment(\.dynamicTypeSize, session.testMode && ProcessInfo.processInfo.arguments.contains("--large-text") ? .accessibility3 : systemTypeSize)
                .preferredColorScheme(session.testMode ? (ProcessInfo.processInfo.arguments.contains("--dark") ? .dark : .light) : nil)
                .task { await session.start() }
                .task(id: "\(session.generation)-\(session.user?.id ?? "guest")-\(session.streamRevision)-\(scenePhase == .active)") {
                    if scenePhase == .active { await session.refreshUnread() }
                }
                .sheet(item: Binding(get: { session.nativePush.destination }, set: { session.nativePush.destination = $0 })) { destination in
                    NavigationStack {
                        Group { switch destination { case .chat(let peer): ChatView(peer: peer); case .note(let id): NoteDetailView(noteID: id) } }
                            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { session.nativePush.destination = nil } } }
                    }
                }
                .task(id: "\(session.generation)-\(session.user?["avatarUrl"].string ?? "")") {
                    profileTabAvatar = nil
                    if session.testMode {
                        if ProcessInfo.processInfo.arguments.contains("--fixture-tab-avatar"), let image = UIImage(named: "ChartCover") { profileTabAvatar = ProfileTabAvatar.rounded(image) }
                        return
                    }
                    guard let url = safeMediaURL(session.user?["avatarUrl"].string) else { return }
                    let image = await ProfileTabAvatar.load(url)
                    if !Task.isCancelled { profileTabAvatar = image }
                }
                .onChange(of: scenePhase) { _, phase in if phase == .active { session.resumeStream(); Task { await session.nativePush.resume() } } else { session.stream.stop(); session.admin.clear(); session.security.clear() } }
        }
    }
}

