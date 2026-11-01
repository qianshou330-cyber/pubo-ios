import SwiftUI

/// Persistent labels and account suffixes follow the mobile website without
/// replacing native text input, autofill, or Dynamic Type.
struct PUBOAccountField<Content: View>: View {
    let title: String
    var symbol: String? = nil
    var suffix: String? = nil
    var prefix: String? = nil
    @ViewBuilder let content: () -> Content
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.medium)).accessibilityIdentifier("account.label." + title)
            HStack(spacing: 8) {
                if let symbol { Image(systemName: symbol).foregroundStyle(PUBOTheme.secondary).accessibilityHidden(true) }
                if let prefix { Text(prefix).foregroundStyle(PUBOTheme.secondary).accessibilityHidden(true) }
                content().frame(minWidth: 40, maxWidth: .infinity).font(.body)
                if let suffix, !typeSize.isAccessibilitySize { Text(suffix).font(.footnote).foregroundStyle(PUBOTheme.secondary).fixedSize() }
            }.padding(.horizontal, 12).frame(minHeight: 48)
                .background(PUBOTheme.panel, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(PUBOTheme.divider, lineWidth: 1))
            if let suffix, typeSize.isAccessibilitySize { Text(suffix).font(.footnote).foregroundStyle(PUBOTheme.secondary) }
        }
    }
}

struct PUBOPasswordField: View {
    let title: String
    @Binding var value: String
    let identifier: String
    var newPassword = false
    @State private var visible = false
    @FocusState private var focused: Bool
    var body: some View {
        PUBOAccountField(title: title, symbol: "lock") {
            HStack(spacing: 0) {
                Group {
                    if visible { TextField(title, text: $value) }
                    else { SecureField(title, text: $value) }
                }.textContentType(newPassword ? .newPassword : .password)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($focused).accessibilityIdentifier(identifier)
                Button {
                    visible.toggle(); focused = true
                } label: {
                    Image(systemName: visible ? "eye.slash" : "eye")
                        .frame(width: 44, height: 44).foregroundStyle(PUBOTheme.secondary)
                }.buttonStyle(.plain).accessibilityLabel(visible ? "隐藏密码" : "显示密码")
                    .accessibilityIdentifier(identifier + ".visibility")
            }
        }
    }
}
