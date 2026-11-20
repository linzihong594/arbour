import DiaryCore
import DiaryState
import Foundation
import Testing

@MainActor
struct ManagementTests {
    @Test func titleAndNaturalDayFiltersCombineWithoutBodySearch() async throws {
        let store = MemoryStore()
        let older = try await store.save(
            document(title: "Café 日记", day: 1_700_000_000), expectedRevision: nil)
        let newer = try await store.save(document(title: "第二天", day: 1_700_086_400), expectedRevision: nil)
        let workspace = DiaryWorkspace(store: store)
        await workspace.open()
        workspace.filter.titleQuery = "cafe"
        #expect(workspace.visibleEntries.map(\.id) == [older.metadata.id])
        workspace.filter.day = newer.metadata.day
        #expect(workspace.visibleEntries.isEmpty)
        workspace.filter.titleQuery = ""
        #expect(workspace.visibleEntries.map(\.id) == [newer.metadata.id])
        workspace.filter.day = nil
        workspace.filter.titleQuery = "只在正文出现"
        #expect(workspace.visibleEntries.isEmpty)
        #expect(workspace.markdown == "只在正文出现的合成内容")
    }

    @Test func trashFlushesLatestDraftAndReopensAfterRestore() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = DiaryRepository(directory: folder)
        let saved = try await store.save(document(), expectedRevision: nil)
        let workspace = DiaryWorkspace(store: store)
        await workspace.open()
        workspace.markdown = "移入前最后一笔 🌿"
        await workspace.trashSelected()
        #expect(workspace.entries.isEmpty)
        #expect(workspace.session == nil)
        await workspace.showTrash(true)
        #expect(workspace.selectedTrashEntry?.id == saved.metadata.id)
        #expect(workspace.session == nil)
        await workspace.restoreSelected()
        #expect(!workspace.isShowingTrash)
        #expect(workspace.markdown == "移入前最后一笔 🌿")
        let reopened = DiaryWorkspace(store: DiaryRepository(directory: folder))
        await reopened.open()
        #expect(reopened.selectedID == saved.metadata.id)
        #expect(reopened.markdown == "移入前最后一笔 🌿")
        #expect(reopened.trashedEntries.isEmpty)
    }

    @Test func failedSaveOrMoveKeepsCurrentDraftAndScope() async throws {
        let store = MemoryStore()
        let saved = try await store.save(document(), expectedRevision: nil)
        let workspace = DiaryWorkspace(store: store)
        await workspace.open()
        workspace.markdown = "尚未保存"
        await store.setFailure(true)
        await workspace.trashSelected()
        await workspace.showTrash(true)
        #expect(!workspace.isShowingTrash)
        #expect(workspace.selectedID == saved.metadata.id)
        #expect(workspace.markdown == "尚未保存")
        #expect(workspace.trashedEntries.isEmpty)
        await store.setFailure(false)
        #expect(await workspace.flush())
        await store.setFailure(true)
        await workspace.trashSelected()
        #expect(workspace.selectedID == saved.metadata.id)
        #expect(workspace.errorMessage != nil)
    }

    @Test func failedRestoreKeepsTrashAndSelection() async throws {
        let store = MemoryStore()
        let saved = try await store.save(document(), expectedRevision: nil)
        let workspace = DiaryWorkspace(store: store)
        await workspace.open()
        await workspace.trashSelected()
        await workspace.showTrash(true)
        await store.setFailure(true)
        await workspace.restoreSelected()
        #expect(workspace.isShowingTrash)
        #expect(workspace.selectedID == saved.metadata.id)
        #expect(workspace.trashedEntries.count == 1)
        #expect(workspace.session == nil)
    }

    @Test func privateExportRequiresUnlockAndCreatesOnlyExplicitFile() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = DiaryRepository(directory: folder.appendingPathComponent("Entries"))
        let saved = try await store.save(document(), expectedRevision: nil)
        let workspace = DiaryWorkspace(store: store)
        await workspace.open()
        #expect(await workspace.encrypt(password: "synthetic-password"))
        let file = folder.appendingPathComponent("chosen.md")
        #expect(await workspace.exportMarkdown(id: saved.metadata.id, to: file) == false)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(await workspace.unlock(password: "synthetic-password"))
        let marker = "仅导出文件包含的合成正文🌿"
        workspace.markdown = marker
        #expect(await workspace.exportMarkdown(id: saved.metadata.id, to: file))
        #expect(try String(contentsOf: file, encoding: .utf8) == marker)
        let container = folder.appendingPathComponent("Entries").appendingPathComponent(
            "\(saved.metadata.id.uuidString.lowercased()).diary.json")
        #expect(try Data(contentsOf: container).range(of: Data(marker.utf8)) == nil)
        await workspace.showTrash(true)
        #expect(workspace.session == nil)
        #expect(workspace.markdown.isEmpty)
        let files = try FileManager.default.subpathsOfDirectory(atPath: folder.path)
        #expect(files.filter { $0.hasSuffix(".md") } == ["chosen.md"])
        #expect(!files.contains { $0.contains(".pending-") })
    }

    @Test func systemLockDuringExportFlushPreventsPlaintextFile() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = MemoryStore()
        let saved = try await store.save(document(), expectedRevision: nil)
        let session = DiarySession(document: saved, store: store)
        #expect(await session.encrypt(password: "synthetic-password"))
        #expect(await session.unlock(password: "synthetic-password"))
        session.editMarkdown("待保存的私密内容")
        await store.setDelay(.milliseconds(80))
        let file = folder.appendingPathComponent("blocked.md")
        let export = Task { await session.exportMarkdown(to: file) }
        try await Task.sleep(for: .milliseconds(20))
        session.lock()
        #expect(await export.value == false)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }

    @Test func staleExportRequestCannotExportAnotherSelection() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = MemoryStore()
        let first = try await store.save(document(), expectedRevision: nil)
        let second = try await store.save(document(title: "另一篇"), expectedRevision: nil)
        let workspace = DiaryWorkspace(store: store)
        await workspace.open(preferredID: first.metadata.id)
        await workspace.select(second.metadata.id)
        #expect(
            await workspace.exportMarkdown(id: first.metadata.id, to: folder.appendingPathComponent("no.md"))
                == false)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }

    private func document(title: String = "合成标题", day: TimeInterval = 1_700_000_000) -> DiaryDocument {
        DiaryDocument(
            metadata: DiaryMetadata(
                title: title, date: Date(timeIntervalSince1970: day), timeZone: TimeZone(secondsFromGMT: 0)!),
            content: .plain(DiaryPayload(markdown: "只在正文出现的合成内容")))
    }

    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "diary-management-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        return folder
    }
}
