import SwiftUI
import UIKit
import PUBOCore

/// Full-width native navigation. Only the opaque background extends below the
/// safe area; buttons stay above the home indicator and content is inset.
struct BottomTabBar: View {
    @Environment(AppSession.self) private var session
    let profileAvatar: UIImage?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                ZStack {
                    Button {
                        if session.selectedTab != tab { session.selectedTab = tab }
                    } label: {
                        VStack(spacing: 2) {
                            icon(tab).frame(width: 28, height: 26)
                            Text(tab.title).font(.caption2).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(session.selectedTab == tab ? PUBOTheme.accent : PUBOTheme.secondary)
                    .accessibilityLabel(tab.title)
                    .accessibilityValue(badgeDescription(tab))
                    .accessibilityAddTraits(session.selectedTab == tab ? .isSelected : [])
                    .accessibilityIdentifier("app.tab." + tab.rawValue)
                    if let badge = badge(tab) {
                        Text(badge)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(Color.red, in: Capsule())
                            .offset(x: 20, y: -16)
                            .allowsHitTesting(false)
                            .accessibilityLabel(badge == "•" ? badgeDescription(tab) : badge)
                            .accessibilityIdentifier("app.tabBadge." + tab.rawValue)
                    }
                }.accessibilityElement(children: .contain)
            }
        }
        .frame(maxWidth: .infinity)
        .background(PUBOTheme.panel.ignoresSafeArea(.container, edges: .bottom))
        .overlay(alignment: .top) { PUBOTheme.divider.frame(height: 0.5) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("app.tabBar")
    }

    @ViewBuilder private func icon(_ tab: AppTab) -> some View {
        if tab == .me, let profileAvatar {
            Image(uiImage: profileAvatar).resizable().scaledToFit()
                .frame(width: 26, height: 26).clipShape(Circle())
        } else {
            Image(systemName: symbol(tab)).font(.system(size: 21))
        }
    }
    private func symbol(_ tab: AppTab) -> String {
        switch tab {
        case .messages: return "bubble.left.and.bubble.right"
        case .friends: return "person.2"
        case .world: return "globe"
        case .me: return "person.crop.circle"
        }
    }
    private func badge(_ tab: AppTab) -> String? {
        switch tab {
        case .messages: return session.badges.chatLabel
        case .friends: return session.pendingFollowRequestBadge
        case .world: return nil
        case .me: return session.badges.notificationLabel
        }
    }
    private func badgeDescription(_ tab: AppTab) -> String {
        guard let value = badge(tab) else { return "" }
        switch tab {
        case .messages: return value == "•" ? "有未读聊天" : value + " 条未读聊天"
        case .friends: return "有待处理关注申请"
        case .world: return ""
        case .me: return value == "•" ? "有未读通知" : value + " 条未读通知"
        }
    }
}

/// The bar disappears for software-keyboard input instead of floating above it.
/// State belongs to this signed-in shell, not a global keyboard singleton.
struct BottomTabBarInset: ViewModifier {
    @Environment(AppSession.self) private var session
    let profileAvatar: UIImage?
    @State private var keyboardVisible = false

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if !keyboardVisible && !session.hidesBottomTabs { BottomTabBar(profileAvatar: profileAvatar) }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let screen = UIScreen.main.bounds
            keyboardVisible = frame.height > 0 && frame.minY < screen.maxY && frame.intersects(screen)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
        .onChange(of: session.generation) { _, _ in keyboardVisible = false }
        .onChange(of: session.selectedTab) { _, _ in
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            keyboardVisible = false
        }
        .onDisappear { keyboardVisible = false }
    }
}

/// A visible conversation leases suppression for its own tab. Multiple nested
/// destinations cannot release one another's lease, and other tabs stay usable.
struct ConversationTabSuppression: ViewModifier {
    @Environment(AppSession.self) private var session
    @State private var lease = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { session.conversationTabLeases[lease] = session.selectedTab }
            .onDisappear { session.conversationTabLeases.removeValue(forKey: lease) }
    }
}
