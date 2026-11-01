import SwiftUI

@main
struct PUBOApp: App {
    @State private var session = AppSession()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var systemTypeSize
    var body: some Scene {
        WindowGroup {
            Group {
                if session.restoring { VStack(spacing: 20) { PUBOBrand(); ProgressView("正在恢复账号…") }.frame(maxWidth: .infinity, maxHeight: .infinity).background(PUBOTheme.background) }
                else if session.user == nil { AuthView() }
                else {
                    TabView(selection: $session.selectedTab) {
                        TimelineView().tabItem { Label("动态", systemImage: "house") }.tag(0)
                        NotificationsView().tabItem { Label("通知", systemImage: "bell") }.tag(1)
                        ChatListView().tabItem { Label("私信", systemImage: "bubble.left.and.bubble.right") }.tag(2)
                        MyAccountView().tabItem { Label("我的", systemImage: "person") }.tag(3)
                    }.id(session.generation).toolbarBackground(PUBOTheme.panel, for: .tabBar).toolbarBackground(.visible, for: .tabBar)
                }
            }.environment(session).tint(PUBOTheme.accent).foregroundStyle(PUBOTheme.text)
                .environment(\.locale, Locale(identifier: "zh_CN"))
                .environment(\.dynamicTypeSize, session.testMode && ProcessInfo.processInfo.arguments.contains("--large-text") ? .accessibility3 : systemTypeSize)
                .preferredColorScheme(session.testMode ? (ProcessInfo.processInfo.arguments.contains("--dark") ? .dark : .light) : nil)
                .task { await session.start() }
                .onChange(of: scenePhase) { _, phase in if phase == .active { session.resumeStream() } else { session.stream.stop() } }
        }
    }
}
