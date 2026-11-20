import AppKit
import DiaryState

@MainActor
final class DiaryAppDelegate: NSObject, NSApplicationDelegate {
    weak var workspace: DiaryWorkspace?
    weak var backup: BackupController?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let workspace else { return .terminateNow }
        Task {
            let saved = await workspace.flush()
            if saved {
                workspace.lockSelected()
                await backup?.performQuitBackupIfNeeded()
            }
            sender.reply(toApplicationShouldTerminate: saved)
        }
        return .terminateLater
    }
}
