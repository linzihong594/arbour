import AppKit
import Foundation

struct EditorCheck: Codable {
    let name: String
    let passed: Bool
    var detail: String? = nil
}

struct EditorReport: Codable {
    let checks: [EditorCheck]
    let characterCount: Int
    let editCount: Int
    let editP50Milliseconds: Double
    let editP95Milliseconds: Double
    let editMaximumMilliseconds: Double
    let measurement: String
}

@MainActor
enum EditorChecks {
    static func run() async throws -> EditorReport {
        var retained: [EditorHarness] = []
        var checks: [EditorCheck] = []

        let composition = EditorHarness(text: "")
        retained.append(composition)
        let input = try await composition.prepare()
        let selection = NSRange(location: NSNotFound, length: 0)
        input.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: selection)
        await EditorHarness.settle(milliseconds: 20)
        let staged = input.hasMarkedText() && composition.model.text.isEmpty
        input.setMarkedText(
            "nihao", selectedRange: NSRange(location: 5, length: 0), replacementRange: selection)
        input.insertText("你好🌿", replacementRange: selection)
        await EditorHarness.settle(milliseconds: 30)
        checks.append(
            EditorCheck(
                name: "marked text stays uncommitted, then Chinese/emoji commits exactly",
                passed: staged && !input.hasMarkedText() && composition.model.text == "你好🌿"))

        let undoHost = EditorHarness(text: "你好🌿")
        retained.append(undoHost)
        let undoView = try await undoHost.prepare()
        undoView.insertText(
            "\n撤销验证", replacementRange: NSRange(location: (undoView.string as NSString).length, length: 0))
        await EditorHarness.settle(milliseconds: 200)
        undoView.breakUndoCoalescing()
        let canUndo = undoView.undoManager?.canUndo == true
        let handled = undoView.tryToPerform(NSSelectorFromString("undo:"), with: nil)
        await EditorHarness.settle(milliseconds: 200)
        let afterUndo = undoHost.model.text
        let viewAfterUndo = undoView.string
        let undone = afterUndo == "你好🌿"
        undoView.tryToPerform(NSSelectorFromString("redo:"), with: nil)
        await EditorHarness.settle(milliseconds: 200)
        checks.append(
            EditorCheck(
                name: "native undo and redo preserve committed Chinese text",
                passed: undone && undoHost.model.text == "你好🌿\n撤销验证",
                detail:
                    "canUndo=\(canUndo), handled=\(handled), afterUndo=\(afterUndo.debugDescription), viewAfterUndo=\(viewAfterUndo.debugDescription), afterRedo=\(undoHost.model.text.debugDescription)"
            ))

        let table = "## 表格\n\n| 时间 | 记录 |\n| --- | --- |\n| 傍晚 | 散步 |\n"
        let tableHost = EditorHarness(text: table)
        retained.append(tableHost)
        let tableView = try await tableHost.prepare()
        tableView.insertText("读书", replacementRange: (tableView.string as NSString).range(of: "散步"))
        await EditorHarness.settle(milliseconds: 30)
        let editedTable = table.replacingOccurrences(of: "散步", with: "读书")
        checks.append(
            EditorCheck(
                name: "editing a GFM table cell preserves complete Markdown structure",
                passed: tableHost.model.text == editedTable))
        tableHost.model.source = true
        await EditorHarness.settle(milliseconds: 30)
        _ = try await tableHost.prepare()
        checks.append(
            EditorCheck(
                name: "source mode preserves table pipes and alignment row",
                passed: tableHost.textView?.string == editedTable))

        let paragraph = "## 合成段落\n\n记录一段值得记住的日常，包含 **粗体** 和 *斜体*。\n\n"
        let longText = String(String(repeating: paragraph, count: 300).prefix(10_000))
        let longHost = EditorHarness(text: longText)
        retained.append(longHost)
        let longView = try await longHost.prepare()
        longHost.layout()
        let initialMatch = longHost.model.text == longText
        var timings: [Double] = []
        for _ in 0..<100 {
            let begin = ContinuousClock.now
            longView.insertText(
                "字", replacementRange: NSRange(location: (longView.string as NSString).length, length: 0))
            longHost.layout()
            await EditorHarness.settle(milliseconds: 10)
            let elapsed = begin.duration(to: .now).components
            timings.append(Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
        }
        checks.append(
            EditorCheck(
                name: "10,000-character document retains 100 consecutive edits",
                passed: initialMatch && longHost.model.text == longText + String(repeating: "字", count: 100)))
        checks += try await EditorSecurityChecks.run()
        for harness in retained { harness.window.orderOut(nil) }
        timings.sort()
        return EditorReport(
            checks: checks, characterCount: longText.count, editCount: timings.count,
            editP50Milliseconds: timings[49], editP95Milliseconds: timings[94],
            editMaximumMilliseconds: timings[99],
            measurement:
                "Release native editor insert + complete TextKit layout + binding/run-loop propagation, including a 10ms settle; offscreen window, not display scanout. Programmatic marked-text test is not a full OS Pinyin candidate-window test."
        )
    }
}
