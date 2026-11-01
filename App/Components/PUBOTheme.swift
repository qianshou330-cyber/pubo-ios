import SwiftUI
import UIKit

/// Matches the site's default l-light / d-green-lime themes, plus PUBO overrides.
/// Keep presentation separate from account permissions and networking.
enum PUBOTheme {
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }
    static let background = adaptive(0xf9f9f9, 0x0c1210)
    static let panel = adaptive(0xffffff, 0x192320)
    static let text = adaptive(0x676767, 0xdee7e4)
    static let secondary = adaptive(0x777777, 0x9caeA7)
    static let accent = adaptive(0x86b300, 0xb4e900)
    static let button = adaptive(0xf2f2f2, 0x23322c)
    static let divider = adaptive(0xe8e8e8, 0x36423f)
    static let ownBubble = adaptive(0xedf4d9, 0x30411b)
    static let registration = Color(red: 45/255, green: 193/255, blue: 0)
    static let radius: CGFloat = 12
}

struct PUBOButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, publish, registration }
    var kind: Kind = .secondary
    var fullWidth = false
    @Environment(\.isEnabled) private var enabled
    private var background: Color {
        switch kind {
        case .primary: return PUBOTheme.accent
        case .secondary: return PUBOTheme.button
        case .publish: return .white
        case .registration: return PUBOTheme.registration
        }
    }
    private var foreground: Color {
        switch kind {
        case .primary: return Color(red: 25/255, green: 35/255, blue: 32/255)
        case .secondary: return PUBOTheme.text
        case .publish: return .black
        case .registration: return .white
        }
    }
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.semibold))
            .padding(.horizontal, 18).padding(.vertical, 11)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 44)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
            .overlay(Capsule().strokeBorder(kind == .publish ? PUBOTheme.divider : .clear, lineWidth: 1))
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
            .contentShape(Capsule())
    }
}

extension View {
    func puboScreen() -> some View {
        foregroundStyle(PUBOTheme.text).tint(PUBOTheme.accent)
            .background(PUBOTheme.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(PUBOTheme.panel, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
    func puboList() -> some View {
        listStyle(.plain).scrollContentBackground(.hidden).puboScreen()
    }
    func puboForm() -> some View {
        scrollContentBackground(.hidden).puboScreen()
    }
    func puboCard(padding: CGFloat = 16) -> some View {
        self.padding(padding).background(PUBOTheme.panel, in: RoundedRectangle(cornerRadius: PUBOTheme.radius))
    }
    func puboListRow() -> some View {
        listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            .listRowSeparator(.hidden).listRowBackground(Color.clear)
    }
    func puboInput() -> some View {
        padding(14).frame(minHeight: 48)
            .background(PUBOTheme.background, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(PUBOTheme.divider, lineWidth: 1))
    }
}

struct PUBOBrand: View {
    var width: CGFloat = 200
    var body: some View {
        Image("Brand").resizable().scaledToFit().frame(width: width, height: width * 221 / 660)
            .shadow(color: .black.opacity(0.32), radius: 3, y: 2)
            .accessibilityLabel("PUBO")
    }
}

/// A native tab selector with the site's underline treatment; wraps at large text sizes.
struct PUBOTimelineSelector: View {
    @Binding var selection: String
    @Environment(\.dynamicTypeSize) private var typeSize
    private let items = [("home", "关注", "house"), ("local", "本站", "building.2"), ("global", "全球", "globe")]
    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        layout {
            ForEach(items, id: \.0) { item in
                Button { selection = item.0 } label: {
                    VStack(spacing: 0) {
                        Label(item.1, systemImage: item.2).font(.subheadline.weight(selection == item.0 ? .bold : .regular))
                            .frame(maxWidth: .infinity, minHeight: 44).padding(.horizontal, 8)
                        Rectangle().fill(selection == item.0 ? PUBOTheme.accent : .clear).frame(height: 3)
                    }
                }.buttonStyle(.plain).foregroundStyle(selection == item.0 ? PUBOTheme.accent : PUBOTheme.secondary)
                    .accessibilityAddTraits(selection == item.0 ? .isSelected : [])
                    .accessibilityIdentifier("timeline." + item.0)
            }
        }.background(PUBOTheme.panel, in: RoundedRectangle(cornerRadius: PUBOTheme.radius))
    }
}

/// H5 distinguishes the pill-shaped entry from the small 6pt submit button.
struct PUBOPostButtonStyle: ButtonStyle {
    var submit = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.bold))
            .padding(.horizontal, submit ? 12 : 18).padding(.vertical, 8)
            .frame(minWidth: 90, minHeight: 34)
            .foregroundStyle(.black)
            .background(configuration.isPressed ? Color(white: 0.9) : .white, in: RoundedRectangle(cornerRadius: submit ? 6 : 24))
            .overlay(RoundedRectangle(cornerRadius: submit ? 6 : 24).strokeBorder(PUBOTheme.divider, lineWidth: 0.5))
            .opacity(enabled ? 1 : 0.7).frame(minHeight: 44)
            .contentShape(Rectangle())
    }
}

struct PUBOChatBubble: Shape {
    let own: Bool
    func path(in rect: CGRect) -> Path {
        let body = CGRect(x: own ? 0 : 4, y: 3, width: rect.width - 4, height: rect.height - 3)
        var path = Path(roundedRect: body, cornerRadius: PUBOTheme.radius)
        if own {
            path.move(to: CGPoint(x: rect.maxX - 16, y: 4))
            path.addLine(to: CGPoint(x: rect.maxX, y: 0))
            path.addLine(to: CGPoint(x: rect.maxX - 5, y: 16))
        } else {
            path.move(to: CGPoint(x: 16, y: 4))
            path.addLine(to: .zero)
            path.addLine(to: CGPoint(x: 5, y: 16))
        }
        path.closeSubpath()
        return path
    }
}
