import AppKit
import SwiftUI

enum DiaryStyle {
    static let accent = Color(red: 0.37, green: 0.43, blue: 0.31)
    static let page = Color(
        nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                NSColor(red: 0.12, green: 0.13, blue: 0.12, alpha: 1)
            } else {
                NSColor(red: 0.99, green: 0.98, blue: 0.955, alpha: 1)
            }
        })
    static let paperBorder = Color(
        nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                NSColor(white: 1.0, alpha: 0.09)
            } else {
                NSColor(red: 0.56, green: 0.50, blue: 0.40, alpha: 0.18)
            }
        })
    static let sidebar = Color(nsColor: .windowBackgroundColor)
}
