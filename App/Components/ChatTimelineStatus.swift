import SwiftUI
import PUBOCore

struct ChatTimelineStatus: View {
    let loaded: Bool
    let loading: Bool
    let isEmpty: Bool
    let error: String?
    let prefix: String
    let retry: () -> Void

    var body: some View {
        if isEmpty {
            VStack(spacing: 12) {
                if let error {
                    Image(systemName: "exclamationmark.bubble")
                    Text(error).font(.subheadline).multilineTextAlignment(.center)
                        .accessibilityIdentifier(prefix + ".loadError")
                    Button("重新加载", action: retry).frame(minWidth: 44, minHeight: 44)
                        .disabled(loading).accessibilityIdentifier(prefix + ".retry")
                } else if !loaded || loading {
                    ProgressView("正在加载消息…").accessibilityIdentifier(prefix + ".loading")
                } else {
                    Label("暂无消息，打个招呼吧", systemImage: "bubble.left.and.bubble.right")
                        .font(.subheadline).foregroundStyle(PUBOTheme.secondary)
                        .accessibilityIdentifier(prefix + ".empty")
                }
            }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct ChatConnectionStatus: View {
    let phase: ChatConnectionPhase
    let synchronizing: Bool
    let prefix: String
    let retry: () -> Void

    var body: some View {
        if phase == .reconnecting || phase == .connecting || synchronizing {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(phase == .reconnecting ? "连接已中断，正在重连…" : (phase == .connecting ? "正在连接…" : "正在同步消息…"))
                    .font(.caption)
                Spacer(minLength: 0)
                if phase == .reconnecting { Button("重试", action: retry).frame(minWidth: 44, minHeight: 44) }
            }.padding(.horizontal, 16).frame(minHeight: 32)
                .background(PUBOTheme.panel).accessibilityIdentifier(prefix + ".connection")
        }
    }
}
