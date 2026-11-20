import AppKit
import Foundation

@MainActor
enum EditorSecurityChecks {
    static func run() async throws -> [EditorCheck] {
        let marker = "SEC005-合成私密正文"
        let host = EditorHarness(text: marker)
        let old = try await host.prepare()
        old.insertText("补记", replacementRange: NSRange(location: (old.string as NSString).length, length: 0))
        await EditorHarness.settle(milliseconds: 50)
        let oldUndo = old.undoManager
        let hadUndo = oldUndo?.canUndo == true
        host.model.visible = false
        await EditorHarness.settle(milliseconds: 80)
        var checks = [
            EditorCheck(
                name: "removed editor clears retained text, delegate, undo and accessibility value",
                passed: hadUndo && old.string.isEmpty && old.delegate == nil
                    && oldUndo?.canUndo != true
                    && !(old.accessibilityValue() ?? "").contains(marker))
        ]

        host.model.text = "重新解锁的合成正文"
        host.model.visible = true
        let reopened = try await host.prepare()
        reopened.tryToPerform(NSSelectorFromString("undo:"), with: nil)
        await EditorHarness.settle(milliseconds: 30)
        checks.append(
            EditorCheck(
                name: "recreated editor cannot undo into a removed private session",
                passed: reopened !== old && reopened.undoManager?.canUndo != true
                    && host.model.text == "重新解锁的合成正文"))

        reopened.insertText(
            "原文切换", replacementRange: NSRange(location: (reopened.string as NSString).length, length: 0))
        await EditorHarness.settle(milliseconds: 30)
        let source = host.model.text
        let sourceUndo = reopened.undoManager
        host.model.source = true
        let sourceView = try await host.prepare()
        checks.append(
            EditorCheck(
                name: "source-mode rebuild clears previous native text and undo while preserving Markdown",
                passed: reopened.string.isEmpty && sourceUndo?.canUndo != true && sourceView.string == source)
        )

        let previousUndo = sourceView.undoManager
        host.model.text = "另一篇普通日记"
        host.model.documentID = "another-synthetic-document"
        let other = try await host.prepare()
        other.tryToPerform(NSSelectorFromString("undo:"), with: nil)
        await EditorHarness.settle(milliseconds: 30)
        checks.append(
            EditorCheck(
                name: "document change clears old native editor and does not expose previous undo",
                passed: sourceView.string.isEmpty && sourceView.delegate == nil
                    && previousUndo?.canUndo != true && host.model.text == "另一篇普通日记"))

        other.setMarkedText(
            "simi", selectedRange: NSRange(location: 4, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
        host.model.visible = false
        await EditorHarness.settle(milliseconds: 80)
        checks.append(
            EditorCheck(
                name: "removing editor discards marked text without committing it into the model",
                passed: other.string.isEmpty && !other.hasMarkedText() && host.model.text == "另一篇普通日记"))
        host.window.orderOut(nil)
        return checks
    }
}
