import SwiftUI
import PUBOCore

struct AuthView: View {
    var addingAccount = false
    @Environment(AppSession.self) private var session
    @State private var flow: AuthFlow?
    @State private var lastEntry = "login"
    @AccessibilityFocusState private var restoredFocus: String?
    @State private var homePath: [HomeDestination] = []
    @State private var songSelection: ChartSongSelection?
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 14
    @ScaledMetric(relativeTo: .title2) private var titleSize: CGFloat = 20
    var body: some View {
        NavigationStack(path: $homePath) {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 0) {
                        Text("PUBO").font(.system(size: titleSize, weight: .bold)).padding(.bottom, 24)
                        Text("通过帖子连接在一起的网络").font(.system(size: bodySize)).multilineTextAlignment(.center)
                        VStack(spacing: 10) {
                            Button("注册") { open(registration: true) }
                                .buttonStyle(PUBOButtonStyle(kind: .registration, fullWidth: true)).accessibilityIdentifier("auth.openRegister").accessibilityFocused($restoredFocus, equals: "register")
                            Button("登录") { open(registration: false) }
                                .buttonStyle(PUBOButtonStyle(kind: .secondary, fullWidth: true)).accessibilityIdentifier("auth.openLogin").accessibilityFocused($restoredFocus, equals: "login")
                        }.padding(.top, 32)
                    }.padding(.horizontal, 32).padding(.top, 48).padding(.bottom, 32)
                        .frame(maxWidth: .infinity)
                        .background {
                            RoundedRectangle(cornerRadius: PUBOTheme.radius).fill(PUBOTheme.panel)
                                .shadow(color: .black.opacity(0.10), radius: 16, y: 8)
                        }
                        .overlay(alignment: .top) { PUBOBrand(width: 220).offset(y: -42).accessibilityIdentifier("pubo.shell") }
                        .padding(.top, 42)
                    if !addingAccount && !session.savedAccounts.isEmpty { NavigationLink("选择已保存的 PUBO 账号") { AccountManagerView() } }
                    policyLinks
                    HomeAnnouncements(refreshID: 0) { homePath.append($0) }
                    HomeChartPanel(refreshID: 0) { destination in
                        if case .history(let key, let song, let chart) = destination { songSelection = ChartSongSelection(key: key, song: song, chart: chart) }
                        else { homePath.append(destination) }
                    }
                    NavigationLink("查看全部站内公告") { AnnouncementsView() }
                    GuestFeed()
                }.frame(maxWidth: 430).padding(.horizontal, 16).padding(.top, 60).padding(.bottom, 32).frame(maxWidth: .infinity)
            }.puboScreen()
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: HomeDestination.self) { $0.view }
                .sheet(item: $songSelection) { ChartSongSheet(selection: $0) }
                .accessibilityHidden(flow != nil)
                .allowsHitTesting(flow == nil)
        }
        .blur(radius: flow == nil ? 0 : 4)
        .overlay {
            if let flow {
                AuthDialog(flow: flow, close: close)
                    .transition(.opacity).zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: flow != nil)
        .onDisappear { flow?.close() }
    }
    private func open(registration: Bool) {
        lastEntry = registration ? "register" : "login"
        flow = AuthFlow(registration: registration, session: session, addingAccount: addingAccount)
    }
    private func close() {
        flow?.close(); flow = nil; restoredFocus = lastEntry
    }
    private var policyLinks: some View {
        Link("隐私政策", destination: URL(string: "https://bolubo.com/privacy.html")!).font(.footnote)
    }
}
