import AppKit
import SwiftUI

/// Tracks whether the hosting NSWindow is actually visible on screen (not minimized, hidden, or fully occluded).
struct WindowVisibilityObserver: NSViewRepresentable {
    @Binding var isVisible: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isVisible: $isVisible)
    }

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.onWindowChange = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: ObserverView, context: Context) {
        context.coordinator.attach(to: nsView.window)
    }

    final class ObserverView: NSView {
        var onWindowChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChange?(window)
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        @Binding var isVisible: Bool
        private weak var observedWindow: NSWindow?

        init(isVisible: Binding<Bool>) {
            _isVisible = isVisible
        }

        func attach(to window: NSWindow?) {
            guard observedWindow !== window else { return }
            if let old = observedWindow {
                NotificationCenter.default.removeObserver(self, name: nil, object: old)
            }
            observedWindow = window
            guard let window else { return }

            updateState(for: window)
            let center = NotificationCenter.default
            let names: [Notification.Name] = [
                NSWindow.didChangeOcclusionStateNotification,
                NSWindow.didMiniaturizeNotification,
                NSWindow.didDeminiaturizeNotification,
            ]
            for name in names {
                center.addObserver(
                    self, selector: #selector(windowVisibilityDidChange(_:)),
                    name: name, object: window)
            }
        }

        @objc private func windowVisibilityDidChange(_ notification: Notification) {
            guard let window = notification.object as? NSWindow ?? observedWindow else { return }
            updateState(for: window)
        }

        private func updateState(for window: NSWindow) {
            let visible = window.occlusionState.contains(.visible) && !window.isMiniaturized
            if isVisible != visible {
                isVisible = visible
            }
        }
    }
}
