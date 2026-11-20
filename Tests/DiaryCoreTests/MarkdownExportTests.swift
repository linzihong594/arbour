import DiaryCore
import Foundation
import Testing

struct MarkdownExportTests {
    @Test func exactMarkdownOnlyInChosenFileWithPrivatePermissions() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("export.md")
        let markdown = "## 合成正文🌿\n\n| A | B |\n|---|---|\n|一|二|\n"
        try MarkdownExport.write(markdown, to: file)
        #expect(try String(contentsOf: file, encoding: .utf8) == markdown)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["export.md"])
        let permissions =
            try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions]
            as? NSNumber
        #expect(permissions?.intValue == 0o600)
    }

    @Test func existingFileAndSymlinkAreNotOverwritten() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let existing = folder.appendingPathComponent("existing.md")
        try Data("old".utf8).write(to: existing)
        let link = folder.appendingPathComponent("link.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: existing)
        #expect(throws: MarkdownExportError.self) { try MarkdownExport.write("new", to: existing) }
        #expect(throws: MarkdownExportError.self) { try MarkdownExport.write("new", to: link) }
        #expect(try String(contentsOf: existing, encoding: .utf8) == "old")
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == 2)
    }

    @Test func invalidDestinationDoesNotCreateFile() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(throws: MarkdownExportError.self) {
            try MarkdownExport.write("secret", to: folder.appendingPathComponent("entry.diary.json"))
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }

    @Test func suggestedNameCannotIntroducePathComponents() {
        let name = MarkdownExport.suggestedName(for: DiaryMetadata(title: " /标题:\\路径\n "))
        #expect(!name.contains("/"))
        #expect(!name.contains("\\"))
        #expect(!name.contains("\n"))
        #expect(name.hasSuffix(".md"))
    }

    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("diary-export-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        return folder
    }
}
