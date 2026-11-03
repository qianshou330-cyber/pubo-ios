import SwiftUI
import UIKit
import PUBOCore

/// UITextView exposes the same selection on iOS 17 and newer. No keyboard recreation on each edit.
struct CursorTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    var focused: Binding<Bool>? = nil
    var enabled = true
    var identifier: String
    var placeholder: String
    var minimumHeight: CGFloat = 44
    var maximumHeight: CGFloat = 140
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator; view.backgroundColor = .clear
        view.font = .preferredFont(forTextStyle: .subheadline); view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = UIEdgeInsets(top: 8, left: 2, bottom: 8, right: 2)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.accessibilityIdentifier = identifier; view.accessibilityLabel = placeholder
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self; context.coordinator.updating = true
        defer { context.coordinator.updating = false }
        view.textColor = UIColor(PUBOTheme.text); view.tintColor = UIColor(PUBOTheme.accent); view.isEditable = enabled
        if view.text != text && view.markedTextRange == nil { view.text = text }
        let range = TextInsertion.clamped(selection, in: view.text ?? "")
        if view.selectedRange != range && view.markedTextRange == nil { view.selectedRange = range }
        if let focused {
            if focused.wrappedValue && !view.isFirstResponder && view.window != nil { view.becomeFirstResponder() }
            else if !focused.wrappedValue && view.isFirstResponder { view.resignFirstResponder() }
        }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        let height = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        return CGSize(width: width, height: min(maximumHeight, max(minimumHeight, height)))
    }
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: CursorTextEditor; var updating = false
        init(_ parent: CursorTextEditor) { self.parent = parent }
        func textViewDidChange(_ view: UITextView) {
            guard !updating else { return }; parent.text = view.text; parent.selection = view.selectedRange; view.invalidateIntrinsicContentSize()
        }
        func textViewDidChangeSelection(_ view: UITextView) {
            // UIKit may notify selection before the text change. Do not redraw with the old binding.
            if !updating && view.text == parent.text { parent.selection = view.selectedRange }
        }
        func textViewDidBeginEditing(_ view: UITextView) { parent.focused?.wrappedValue = true }
        func textViewDidEndEditing(_ view: UITextView) { parent.focused?.wrappedValue = false }
    }
}
