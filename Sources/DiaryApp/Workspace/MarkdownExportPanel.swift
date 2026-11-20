import AppKit
import DiaryCore
import DiaryState
import UniformTypeIdentifiers

@MainActor
enum MarkdownExportPanel {
    static func present(for workspace: DiaryWorkspace, initialDirectory: URL? = nil) {
        guard !workspace.isBusy, !workspace.isLocked, let document = workspace.selectedEntry else { return }
        let id = document.metadata.id
        let panel = NSSavePanel()
        panel.title = "导出 Markdown"
        panel.prompt = "导出"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = MarkdownExport.suggestedName(for: document.metadata)
        panel.canCreateDirectories = true
        panel.directoryURL = initialDirectory
        panel.message =
            document.content.isEncrypted
            ? "将导出未加密的正文。请选择一个新的 .md 文件并妥善保管；已有文件不会被覆盖。"
            : "请选择一个新的 .md 文件。导出包含原始 Markdown 正文，已有文件不会被覆盖。"
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let destination = panel.url else { return }
            Task { await workspace.exportMarkdown(id: id, to: destination) }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }
}
