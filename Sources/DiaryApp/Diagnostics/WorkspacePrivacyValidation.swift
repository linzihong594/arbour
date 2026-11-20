import AppKit
import DiaryCore
import DiaryPlatform
import DiaryState
import Foundation

/// Development-only checks on the live window, enabled only with an explicit synthetic library.
@MainActor
enum WorkspacePrivacyValidation {
    static func run(workspace: DiaryWorkspace, output: URL) async throws {
        guard workspace.entries.count == 2,
            let privateEntry = workspace.entries.first(where: \.isEncrypted),
            let ordinary = workspace.entries.first(where: { !$0.isEncrypted }),
            privateEntry.id.uuidString == "20202020-2020-4020-8020-202020202020",
            ordinary.id.uuidString == "10101010-1010-4010-8010-101010101010",
            let window = NSApp.windows.first(where: { $0.contentView != nil })
        else { throw PlatformError.message("Expected the two generated synthetic diary fixtures") }
        let marker = "SEC005-NATIVE-合成补记"
        await workspace.select(privateEntry.id)
        guard await workspace.unlock(password: "M2-synthetic-password-2026") else {
            throw PlatformError.message("Synthetic unlock failed")
        }
        await settle()
        let privateView = try editor(in: window)
        privateView.insertText(
            "\n" + marker,
            replacementRange: NSRange(location: (privateView.string as NSString).length, length: 0))
        await settle()
        let undo = privateView.undoManager
        try require(undo?.canUndo == true, "Native edit must create undo history")
        // This is the process-local center, not a system-wide screen-lock notification.
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        await settle()
        try require(
            workspace.isLocked && workspace.markdown.isEmpty, "Local session event must lock the diary")
        try require(
            privateView.string.isEmpty && privateView.delegate == nil && undo?.canUndo != true,
            "Lock must revoke the retained editor and undo stack")
        _ = NSApp.sendAction(NSSelectorFromString("undo:"), to: nil, from: nil)
        try require(workspace.markdown.isEmpty, "Responder-chain undo must not unlock a diary")
        try require(await workspace.flush(), "Locked draft must finish saving")
        let refused = await workspace.exportMarkdown(
            id: privateEntry.id,
            to: output.deletingLastPathComponent().appendingPathComponent("refused.md"))
        try require(!refused, "Locked export must be refused")
        workspace.errorMessage = nil
        workspace.session?.errorMessage = nil
        workspace.filter.titleQuery = marker
        try require(workspace.visibleEntries.isEmpty, "Private body must not be searchable")
        workspace.filter = DiaryFilter()
        try require(await workspace.unlock(password: "M2-synthetic-password-2026"), "Unlock must still work")
        await settle()
        let reopened = try editor(in: window)
        try require(reopened.string.contains(marker), "Committed private edit must survive lock")
        await workspace.select(ordinary.id)
        await settle()
        try require(reopened.string.isEmpty && reopened.delegate == nil, "Switch must revoke the old editor")
        let ordinaryView = try editor(in: window)
        _ = ordinaryView.tryToPerform(NSSelectorFromString("undo:"), with: nil)
        try require(!workspace.markdown.contains(marker), "New diary undo must not expose private content")
        let title = String(repeating: "用于窄窗口回归的合成长标题🌿", count: 20)
        workspace.setTitle(title)
        try require(await workspace.flush(), "Long title must save without truncation")
        window.setContentSize(NSSize(width: 820, height: 580))
        await settle()
        guard let root = window.contentView else { throw PlatformError.message("Missing content view") }
        let titleFields = fields(in: root).filter { $0.stringValue == title }
        try require(!titleFields.isEmpty, "Long title field must remain present")
        try require(
            titleFields.allSatisfy { root.bounds.contains($0.convert($0.bounds, to: root)) },
            "Title field must fit the minimum-size window")
        let report: [String: Any] = [
            "local_session_notification_locks": true,
            "retained_editor_and_undo_cleared": true,
            "responder_undo_does_not_unlock": true,
            "locked_pending_draft_saved": true,
            "locked_export_refused": true,
            "private_body_not_searchable": true,
            "reunlock_preserves_edit": true,
            "switch_does_not_expose_previous_undo": true,
            "long_title_character_count": title.count,
            "minimum_content_size": [820, 580],
            "long_title_field_contained": true,
            "real_system_screen_lock_tested": false,
            "normal_library_accessed": false,
        ]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: output, options: .atomic)
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw PlatformError.message(message) }
    }

    private static func settle() async { try? await Task.sleep(for: .milliseconds(180)) }

    private static func editor(in window: NSWindow) throws -> NSTextView {
        func find(_ view: NSView) -> NSTextView? {
            if let text = view as? NSTextView, !text.isFieldEditor { return text }
            return view.subviews.lazy.compactMap(find).first
        }
        guard let root = window.contentView, let text = find(root) else {
            throw PlatformError.message("Native editor missing")
        }
        window.makeFirstResponder(text)
        return text
    }

    private static func fields(in view: NSView) -> [NSTextField] {
        (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap(fields)
    }
}
