import AppKit
import SwiftUI

/// Owns the native subtree so removal can revoke its delegate, text and undo history synchronously.
struct ClearingEditorHost: NSViewRepresentable {
    let content: AnyView

    func makeNSView(context: Context) -> EditorHostingView { EditorHostingView(rootView: content) }
    func updateNSView(_ view: EditorHostingView, context: Context) { view.rootView = content }
    static func dismantleNSView(_ view: EditorHostingView, coordinator: ()) {
        view.clearEditor()
        view.rootView = AnyView(EmptyView())
    }

    final class EditorHostingView: NSHostingView<AnyView> {
        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if window != nil && newWindow == nil { clearEditor() }
            super.viewWillMove(toWindow: newWindow)
        }

        func clearEditor() {
            clearText(in: self)
        }

        private func clearText(in view: NSView) {
            if let text = view as? NSTextView, !text.isFieldEditor {
                text.undoManager?.removeAllActions()
                if text.window?.firstResponder === text { text.window?.makeFirstResponder(nil) }
                text.delegate = nil
                text.allowsUndo = false
                text.isEditable = false
                text.inputContext?.discardMarkedText()
                text.string = ""
                text.setAccessibilityValue("")
            }
            for child in view.subviews { clearText(in: child) }
        }
    }
}
