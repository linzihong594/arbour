import AppKit
import DiaryState
import SwiftUI

/// Keeps SwiftUI's window delegate while interposing an asynchronous save before close.
struct WindowSaveGuard: NSViewRepresentable {
    let workspace: DiaryWorkspace

    func makeCoordinator() -> Coordinator { Coordinator(workspace: workspace) }
    func makeNSView(context: Context) -> WindowObserverView {
        let view = WindowObserverView()
        view.attached = { [weak coordinator = context.coordinator] window in coordinator?.attach(window) }
        return view
    }
    func updateNSView(_ nsView: WindowObserverView, context: Context) {}

    final class WindowObserverView: NSView {
        var attached: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { attached?(window) }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSWindowDelegate {
        let workspace: DiaryWorkspace
        // Objective-C forwarding hooks are nonisolated; AppKit owns and calls this weak delegate on its UI thread.
        nonisolated(unsafe) weak var original: (any NSWindowDelegate)?
        weak var window: NSWindow?
        var isClosing = false
        var mayClose = false

        init(workspace: DiaryWorkspace) { self.workspace = workspace }

        func attach(_ window: NSWindow) {
            guard self.window !== window else { return }
            original = window.delegate
            self.window = window
            window.delegate = self
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            if mayClose {
                mayClose = false
                return original?.windowShouldClose?(sender) ?? true
            }
            guard !isClosing else { return false }
            isClosing = true
            Task {
                if await workspace.flush() {
                    workspace.lockSelected()
                    mayClose = true
                    sender.performClose(nil)
                }
                isClosing = false
            }
            return false
        }

        override func responds(to selector: Selector!) -> Bool {
            MainActor.assumeIsolated {
                super.responds(to: selector) || original?.responds(to: selector) == true
            }
        }

        override func forwardingTarget(for selector: Selector!) -> Any? {
            original?.responds(to: selector) == true ? original : super.forwardingTarget(for: selector)
        }
    }
}
