import DiaryCore
import DiaryState
import Foundation
import Testing

@MainActor
struct AutosaveTests {
    @Test func debounceSavesLatestDraft() async throws {
        let store = MemoryStore()
        let saved = try await store.save(document(), expectedRevision: nil)
        let autosave = DiaryAutosave(document: saved, store: store, delay: .milliseconds(20))
        for number in 1...10 {
            var draft = autosave.document
            draft.metadata.title = "版本 \(number)"
            autosave.update(draft)
        }
        try await Task.sleep(for: .milliseconds(120))
        #expect(autosave.status == .saved)
        #expect(try await store.load(id: saved.metadata.id).metadata.title == "版本 10")
        #expect(await store.writeCount == 2)
    }

    @Test func editingDuringSlowSaveDrainsLatestGeneration() async throws {
        let store = MemoryStore()
        let saved = try await store.save(document(), expectedRevision: nil)
        await store.setDelay(.milliseconds(60))
        let autosave = DiaryAutosave(document: saved, store: store, delay: .seconds(10))
        var draft = saved
        draft.metadata.title = "第一版"
        autosave.update(draft)
        let save = Task { await autosave.flush() }
        try await Task.sleep(for: .milliseconds(20))
        draft.metadata.title = "保存期间的新版本"
        autosave.update(draft)
        #expect(await save.value)
        #expect(try await store.load(id: saved.metadata.id).metadata.title == "保存期间的新版本")
        #expect(autosave.document.metadata.revision == 3)
    }

    @Test func failedSaveRetainsDraftAndCanRetry() async throws {
        let store = MemoryStore()
        let saved = try await store.save(document(), expectedRevision: nil)
        let autosave = DiaryAutosave(document: saved, store: store, delay: .seconds(10))
        var draft = saved
        draft.metadata.title = "未丢失的修改"
        autosave.update(draft)
        await store.setFailure(true)
        #expect(await autosave.flush() == false)
        #expect(autosave.status.failure != nil)
        #expect(autosave.document.metadata.title == "未丢失的修改")
        #expect(try await store.load(id: saved.metadata.id).metadata.title == saved.metadata.title)
        await store.setFailure(false)
        #expect(await autosave.flush())
        #expect(try await store.load(id: saved.metadata.id).metadata.title == "未丢失的修改")
    }

    @Test func navigationRefusesToLoseFailedDraft() async throws {
        let store = MemoryStore()
        _ = try await store.save(document(), expectedRevision: nil)
        let workspace = DiaryWorkspace(store: store)
        await workspace.open()
        let id = workspace.selectedID
        workspace.markdown = "未保存的内容"
        await store.setFailure(true)
        await workspace.addEntry()
        #expect(workspace.selectedID == id)
        #expect(workspace.markdown == "未保存的内容")
        #expect(workspace.errorMessage != nil)
    }

    @Test func encryptedSessionAutosavesCiphertextAndReopensLocked() async throws {
        let store = MemoryStore()
        let saved = try await store.save(document(), expectedRevision: nil)
        let session = DiarySession(document: saved, store: store)
        #expect(await session.encrypt(password: "synthetic-test-password"))
        #expect(session.isLocked)
        #expect(await session.unlock(password: "wrong-password") == false)
        #expect(session.isLocked)
        #expect(await session.unlock(password: "synthetic-test-password"))
        session.editMarkdown("加密后修改的合成正文")
        #expect(await session.autosave.flush())
        session.lock()
        #expect(session.text == nil)
        let reopened = DiarySession(document: try await store.load(id: saved.metadata.id), store: store)
        #expect(reopened.isLocked)
        #expect(await reopened.unlock(password: "synthetic-test-password"))
        #expect(reopened.text == "加密后修改的合成正文")
    }

    @Test func failedEncryptionCommitDoesNotPretendDiskIsProtected() async throws {
        let store = MemoryStore()
        let saved = try await store.save(document(), expectedRevision: nil)
        let session = DiarySession(document: saved, store: store)
        await store.setFailure(true)
        #expect(await session.encrypt(password: "synthetic-test-password") == false)
        #expect(!session.document.content.isEncrypted)
        #expect(session.text == "合成正文")
        #expect(session.errorMessage != nil)
        #expect(try await store.load(id: saved.metadata.id) == saved)
    }

    private func document() -> DiaryDocument {
        DiaryDocument(metadata: DiaryMetadata(title: "合成标题"), content: .plain(DiaryPayload(markdown: "合成正文")))
    }
}

actor MemoryStore: DiaryStore {
    var documents: [UUID: DiaryDocument] = [:]
    var trashed: [UUID: DiaryDocument] = [:]
    var writeCount = 0
    private var fails = false
    private var delay: Duration = .zero
    func setFailure(_ value: Bool) { fails = value }
    func setDelay(_ value: Duration) { delay = value }
    func index() -> DiaryIndex {
        DiaryIndex(
            entries: documents.values.map(\.summary).sorted(by: DiarySummary.newestFirst),
            trashedEntries: trashed.values.map(\.summary).sorted(by: DiarySummary.newestFirst))
    }
    func load(id: UUID) throws -> DiaryDocument { try #require(documents[id]) }
    func save(_ document: DiaryDocument, expectedRevision: UInt64?) async throws -> DiaryDocument {
        if delay > .zero { try await Task.sleep(for: delay) }
        if fails { throw CocoaError(.fileWriteOutOfSpace) }
        guard documents[document.metadata.id]?.metadata.revision == expectedRevision else {
            throw DiaryStoreError.conflict
        }
        var saved = document
        saved.metadata.revision = (expectedRevision ?? 0) + 1
        documents[saved.metadata.id] = saved
        writeCount += 1
        return saved
    }

    func trash(id: UUID, expectedRevision: UInt64) throws -> DiarySummary {
        if fails { throw CocoaError(.fileWriteNoPermission) }
        guard let document = documents[id], document.metadata.revision == expectedRevision,
            trashed[id] == nil
        else { throw DiaryStoreError.conflict }
        trashed[id] = document
        documents[id] = nil
        return document.summary
    }

    func restore(id: UUID, expectedRevision: UInt64) throws -> DiaryDocument {
        if fails { throw CocoaError(.fileWriteNoPermission) }
        guard let document = trashed[id], document.metadata.revision == expectedRevision,
            documents[id] == nil
        else { throw DiaryStoreError.conflict }
        documents[id] = document
        trashed[id] = nil
        return document
    }
}
