import AppKit
import DiaryEditing
import SwiftUI

@MainActor
final class EditorModel: ObservableObject {
    @Published var text: String
    @Published var source = false
    @Published var visible = true
    @Published var documentID = "synthetic-editor-probe"
    init(text: String) { self.text = text }
}

private struct ProbeHost: View {
    @ObservedObject var model: EditorModel
    var body: some View {
        if model.visible {
            DiaryEditorSurface(text: $model.text, documentID: model.documentID, showsSource: model.source)
        }
    }
}

@MainActor
final class EditorHarness {
    let model: EditorModel
    let window: NSWindow
    private(set) var textView: NSTextView?

    init(text: String) {
        model = EditorModel(text: text)
        window = NSWindow(
            contentRect: NSRect(x: -30000, y: -30000, width: 900, height: 650),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ProbeHost(model: model))
        window.orderFrontRegardless()
    }

    func prepare() async throws -> NSTextView {
        await Self.settle(milliseconds: 180)
        guard let root = window.contentView, let textView = findTextView(root) else {
            throw EditorProbeError.failed("Native NSTextView was not created")
        }
        self.textView = textView
        window.makeFirstResponder(textView)
        return textView
    }

    func layout() {
        window.contentView?.layoutSubtreeIfNeeded()
        if let manager = textView?.textLayoutManager, let content = manager.textContentManager {
            manager.ensureLayout(for: content.documentRange)
        }
    }

    static func settle(milliseconds: Int) async {
        let deadline = Date().addingTimeInterval(Double(milliseconds) / 1000)
        while Date() < deadline {
            pump()
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    private static func pump() { RunLoop.main.run(until: Date().addingTimeInterval(0.001)) }

    private func findTextView(_ view: NSView) -> NSTextView? {
        if let text = view as? NSTextView { return text }
        for child in view.subviews {
            if let text = findTextView(child) { return text }
        }
        return nil
    }
}

enum EditorProbeError: LocalizedError {
    case failed(String)
    var errorDescription: String? {
        if case .failed(let message) = self { message } else { "Editor probe failed" }
    }
}
