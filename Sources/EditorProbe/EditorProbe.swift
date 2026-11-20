import AppKit
import DiaryEditing
import Foundation
import SwiftUI

@main
enum EditorProbe {
    @MainActor static func main() async {
        _ = NSApplication.shared
        NSApplication.shared.setActivationPolicy(.accessory)
        do {
            let report = try await EditorChecks.run()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(report)
            if CommandLine.arguments.count > 1 {
                try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
            }
            print(String(decoding: data, as: UTF8.self))
            exit(report.checks.allSatisfy(\.passed) ? EXIT_SUCCESS : EXIT_FAILURE)
        } catch {
            FileHandle.standardError.write(Data("FAIL: \(error.localizedDescription)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }
}
