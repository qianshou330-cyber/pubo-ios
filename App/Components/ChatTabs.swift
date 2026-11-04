import SwiftUI
import PUBOCore

struct ChatTab: Identifiable {
    let id: String
    let title: String
    let icon: String
}

struct ChatTabs: View {
    @Binding var selection: String
    let items: [ChatTab]
    var prefix = "chat.tab."
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(items) { item in
                    Button { selection = item.id } label: {
                        VStack(spacing: 0) {
                            Label(item.title, systemImage: item.icon).font(.subheadline.weight(selection == item.id ? .semibold : .regular))
                                .fixedSize().frame(minHeight: 44).padding(.horizontal, 8)
                            Capsule().fill(selection == item.id ? PUBOTheme.accent : .clear).frame(height: 3)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier(prefix + item.id)
                        .accessibilityAddTraits(selection == item.id ? .isSelected : [])
                }
            }.padding(.horizontal, 12)
        }.scrollIndicators(.hidden).background(PUBOTheme.panel)
            .overlay(alignment: .bottom) { Rectangle().fill(PUBOTheme.divider).frame(height: 0.5) }
    }
}

struct ChatDateSeparator: View {
    let text: String
    var body: some View {
        HStack(spacing: 12) { line; Text(text).font(.caption).foregroundStyle(PUBOTheme.secondary); line }
            .padding(.vertical, 8).accessibilityLabel("鏃ユ湡 " + text)
    }
    private var line: some View { Rectangle().fill(PUBOTheme.divider).frame(height: 0.5) }
}

/// Only stream insertions opt in; initial pages, restored rows and search context stay still.
struct ChatMessageEntrance: ViewModifier {
    let animate: Bool
    let distance: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var appeared = false
    func body(content: Content) -> some View {
        content.opacity(animate && !appeared ? 0 : 1).offset(y: animate && !appeared && !reduced ? distance : 0)
            .onAppear {
                guard animate else { appeared = true; return }
                withAnimation(.timingCurve(0, 0.5, 0.5, 1, duration: 0.2)) { appeared = true }
            }
    }
}

extension View {
    @ViewBuilder func chatNavigationTitle(_ title: String, embedded: Bool) -> some View {
        if embedded { self } else { self.navigationTitle(title) }
    }
}

struct ChatReactionFlow: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { arrange(subviews, width: proposal.width ?? 320).size }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(subviews, width: bounds.width)
        for (index, point) in result.points.enumerated() { subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified) }
    }
    private func arrange(_ subviews: Subviews, width: CGFloat) -> (size: CGSize, points: [CGPoint]) {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, used: CGFloat = 0
        var points: [CGPoint] = []
        for item in subviews {
            let size = item.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + 8; rowHeight = 0 }
            points.append(CGPoint(x: x, y: y)); x += size.width + 8
            used = max(used, x - 8); rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: min(width, used), height: y + rowHeight), points)
    }
}
