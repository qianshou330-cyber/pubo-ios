import SwiftUI
import PUBOCore

@main
struct PUBOApp: App {
    @UIApplicationDelegateAdaptor(NativeAppDelegate.self) private var appDelegate
    @State private var session = AppSession()
    @State private var profileTabAvatar: UIImage?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var systemTypeSize
    var body: some Scene {
        WindowGroup {
            let largeTestText = session.testMode && ProcessInfo.processInfo.arguments.contains("--large-text")
            Group {
                if session.restoring { AppLaunchSkeleton() }
                else if session.user == nil { AuthView() }
                else {
                    TabView(selection: $session.selectedTab) {
                        ChatListView().tabItem { Label("消息", systemImage: "bubble.left.and.bubble.right") }.badge(session.badges.chatLabel).tag(AppTab.messages)
                        FriendsView().tabItem { Label("好友", systemImage: "person.2") }.badge(session.pendingFollowRequestBadge).tag(AppTab.friends)
                        TimelineView().tabItem { Label("世界圈", systemImage: "globe") }.tag(AppTab.world)
                        MyAccountView().tabItem {
                            if let profileTabAvatar { Image(uiImage: profileTabAvatar).renderingMode(.original); Text("我的") }
                            else { Label("我的", systemImage: "person.crop.circle") }
                        }.badge(session.badges.notificationLabel).tag(AppTab.me)
                    }.id(session.generation).toolbarBackground(PUBOTheme.panel, for: .tabBar).toolbarBackground(.visible, for: .tabBar)
                }
            }.environment(session).tint(PUBOTheme.accent).foregroundStyle(PUBOTheme.text)
                .environment(\.locale, Locale(identifier: "zh_CN"))
                .environment(\.dynamicTypeSize, largeTestText ? .accessibility3 : systemTypeSize)
                .modifier(TimelineWindowTypeSize(largeTestText: largeTestText))
                .preferredColorScheme(session.testMode && !ProcessInfo.processInfo.arguments.contains("--system-appearance") ? (ProcessInfo.processInfo.arguments.contains("--dark") ? .dark : .light) : nil)
                .task { await session.start() }
                .task(id: "\(session.generation)-\(session.user?.id ?? "guest")-\(session.streamRevision)-\(scenePhase == .active)") {
                    if scenePhase == .active { await session.refreshUnread() }
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
                .onChange(of: scenePhase) { _, phase in
                    #if DEBUG
                    if phase == .background { RefreshDiagnostics.shared.record(.sceneBackground) }
                    if phase == .active { RefreshDiagnostics.shared.record(.sceneActive) }
                    #endif
                    if phase == .active { session.resumeStream(); Task { await session.nativePush.resume() } } else { session.stream.stop(); session.admin.clear(); session.security.clear() } }
        }
    }
}

extension EnvironmentValues {
    @Entry var timelineWindowTypeSize: DynamicTypeSize = .large
}

/// The window view receives the device's text size, including changes while the app is open.
private struct TimelineWindowTypeSize: ViewModifier {
    @Environment(\.dynamicTypeSize) private var windowSize
    let largeTestText: Bool

    func body(content: Content) -> some View {
        content.environment(\.timelineWindowTypeSize, largeTestText ? .accessibility3 : windowSize)
    }
}

