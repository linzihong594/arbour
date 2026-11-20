import AppKit
import DiaryState

@MainActor
final class DiaryAppDelegate: NSObject, NSApplicationDelegate {
    weak var workspace: DiaryWorkspace?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let workspace else { return .terminateNow }
        Task {
            let saved = await workspace.flush()
            if saved { workspace.lockSelected() }
            sender.reply(toApplicationShouldTerminate: saved)
        }
        return .terminateLater
    }
}
