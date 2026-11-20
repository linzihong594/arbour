import AppKit
import SwiftUI

/// NSTextView's programmatic undo can omit its change callback. Resync through the public delegate API.
struct UndoBindingBridge: NSViewRepresentable {
    func makeNSView(context: Context) -> UndoObserverView { UndoObserverView() }
    func updateNSView(_ nsView: UndoObserverView, context: Context) {}
    static func dismantleNSView(_ nsView: UndoObserverView, coordinator: ()) { nsView.stopObserving() }

    final class UndoObserverView: NSView {
        private var observations: [any NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopObserving()
            guard window != nil else { return }
            for name in [Notification.Name.NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange] {
                observations.append(
                    NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
                        [weak self] notification in
                        let managerID = (notification.object as AnyObject?).map(ObjectIdentifier.init)
                        MainActor.assumeIsolated { self?.synchronize(managerID: managerID) }
                    })
            }
        }

        func stopObserving() {
            for observation in observations { NotificationCenter.default.removeObserver(observation) }
            observations.removeAll()
        }

        private func synchronize(managerID: ObjectIdentifier?) {
            guard let root = window?.contentView, let textView = findEditor(root),
                let manager = textView.undoManager, ObjectIdentifier(manager) == managerID
            else { return }
            textView.delegate?.textDidChange?(
                Notification(name: NSText.didChangeNotification, object: textView))
        }

        private func findEditor(_ view: NSView) -> NSTextView? {
            if let text = view as? NSTextView, !text.isFieldEditor { return text }
            for child in view.subviews {
                if let editor = findEditor(child) { return editor }
            }
            return nil
        }
    }
}
