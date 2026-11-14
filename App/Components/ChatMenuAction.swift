import SwiftUI
import UIKit

/// One command list feeds SwiftUI context/overflow menus and TextKit's edit menu.
/// System selection commands remain UIKit-owned; "复制文字" copies the whole message.
struct ChatMenuAction: Identifiable {
    let id: String
    let title: String
    var destructive = false
    var enabled = true
    let perform: () -> Void

    var uiAction: UIAction {
        var attributes: UIMenuElement.Attributes = []
        if destructive { attributes.insert(.destructive) }
        if !enabled { attributes.insert(.disabled) }
        return UIAction(title: title, identifier: UIAction.Identifier(id), attributes: attributes) { _ in
            guard enabled else { return }
            perform()
        }
    }
}

struct ChatMenuButtons: View {
    let actions: [ChatMenuAction]
    var body: some View {
        ForEach(actions) { action in
            Button(action.title, role: action.destructive ? .destructive : nil) { action.perform() }
                .disabled(!action.enabled).accessibilityIdentifier(action.id)
        }
    }
}
