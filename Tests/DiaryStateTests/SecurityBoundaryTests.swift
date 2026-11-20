import DiaryCore
import DiaryState
import Foundation
import Testing

@MainActor
struct SecurityBoundaryTests {
    @Test func passwordValidationAndCancelDoNotChangeStoredDocument() async throws {
        let (store, workspace) = try await fixture()
        let original = try #require(workspace.selectedEntry)
        for (password, confirmation) in [("", ""), ("short", "short"), ("long-password", "different")] {
            let prompt = DiaryPasswordPrompt(workspace: workspace)
            prompt.password = password
            prompt.confirmation = confirmation
            #expect(await prompt.submit() == false)
            #expect(prompt.errorMessage != nil)
            #expect(prompt.password.isEmpty && prompt.confirmation.isEmpty)
        }
        let cancelled = DiaryPasswordPrompt(workspace: workspace)
        cancelled.password = "synthetic-password"
        cancelled.confirmation = cancelled.password
        cancelled.cancel()
        #expect(await cancelled.submit() == false)
        #expect(cancelled.password.isEmpty && cancelled.confirmation.isEmpty)
        #expect(try await store.load(id: original.metadata.id) == original)
        #expect(await store.writeCount == 1)
    }

    @Test func passwordPromptEncryptsAndWrongPasswordCanRetryWithoutRetainingInput() async throws {
        let (_, workspace) = try await fixture()
        let creation = DiaryPasswordPrompt(workspace: workspace)
        creation.password = "synthetic-password"
        creation.confirmation = creation.password
        #expect(await creation.submit())
        #expect(workspace.isLocked)
        #expect(!creation.isUnlocking)
        #expect(creation.password.isEmpty && creation.confirmation.isEmpty)
        let unlock = DiaryPasswordPrompt(workspace: workspace)
        unlock.password = "wrong-password"
        #expect(await unlock.submit() == false)
        #expect(workspace.isLocked && workspace.markdown.isEmpty)
        #expect(unlock.errorMessage != nil && unlock.password.isEmpty)
        unlock.password = "synthetic-password"
        #expect(await unlock.submit())
        #expect(unlock.errorMessage == nil && unlock.password.isEmpty)
        #expect(workspace.markdown == "合成正文")
        unlock.cancel()  // Successful sheet dismissal must not immediately relock the diary.
        #expect(!workspace.isLocked)
    }

    @Test func encryptionFailureIsReportedAndCanRetry() async throws {
        let (store, workspace) = try await fixture()
        let prompt = DiaryPasswordPrompt(workspace: workspace)
        await store.setFailure(true)
        prompt.password = "synthetic-password"
        prompt.confirmation = prompt.password
        #expect(await prompt.submit() == false)
        #expect(prompt.errorMessage != nil)
        #expect(workspace.selectedEntry?.content.isEncrypted == false)
        #expect(workspace.markdown == "合成正文")
        await store.setFailure(false)
        prompt.password = "synthetic-password"
        prompt.confirmation = prompt.password
        #expect(await prompt.submit())
        #expect(workspace.isLocked)
    }

    @Test func passwordPromptCannotTargetAnotherOrReopenedSession() async throws {
        let (store, workspace) = try await fixture()
        let first = try #require(workspace.selectedID)
        let second = try await store.save(document(title: "另一篇"), expectedRevision: nil)
        let prompt = DiaryPasswordPrompt(workspace: workspace)
        prompt.password = "synthetic-password"
        prompt.confirmation = prompt.password
        await workspace.select(second.metadata.id)
        #expect(await prompt.submit() == false)
        await workspace.select(first)
        prompt.password = "synthetic-password"
        prompt.confirmation = prompt.password
        #expect(await prompt.submit() == false)
        #expect(workspace.selectedEntry?.content.isEncrypted == false)
        #expect(try await store.load(id: second.metadata.id).content.isEncrypted == false)
    }

    @Test func cancellingInFlightUnlockCannotReintroducePlaintext() async throws {
        let (_, workspace) = try await fixture()
        #expect(await workspace.encrypt(password: "synthetic-password"))
        let prompt = DiaryPasswordPrompt(workspace: workspace)
        prompt.password = "synthetic-password"
        let operation = Task { await prompt.submit() }
        for _ in 0..<1000 {
            if prompt.isWorking { break }
            await Task.yield()
        }
        #expect(prompt.isWorking)
        prompt.cancel()
        #expect(await operation.value == false)
        #expect(workspace.isLocked && workspace.markdown.isEmpty)
        #expect(prompt.password.isEmpty && prompt.confirmation.isEmpty)
    }

    @Test func systemLockInvalidatesPendingUnlock() async throws {
        let (_, workspace) = try await fixture()
        #expect(await workspace.encrypt(password: "synthetic-password"))
        let operation = Task { await workspace.unlock(password: "synthetic-password") }
        for _ in 0..<1000 {
            if workspace.session?.isBusy == true { break }
            await Task.yield()
        }
        #expect(workspace.session?.isBusy == true)
        workspace.lockSelected()
        #expect(await operation.value == false)
        #expect(workspace.isLocked && workspace.markdown.isEmpty)
    }

    @Test func staleEditorCannotWriteIntoNewSelectionOrFreshUnlock() async throws {
        let (store, workspace) = try await fixture()
        let oldToken = try #require(workspace.editorIdentity)
        let second = try await store.save(document(title: "另一篇"), expectedRevision: nil)
        await workspace.select(second.metadata.id)
        workspace.setMarkdown("旧编辑器的私密回调", from: oldToken)
        workspace.setTitle("旧标题回调", from: oldToken)
        #expect(workspace.markdown == "合成正文")
        #expect(workspace.selectedEntry?.metadata.title == "另一篇")
        #expect(await workspace.encrypt(password: "synthetic-password"))
        #expect(await workspace.unlock(password: "synthetic-password"))
        let unlockedToken = try #require(workspace.editorIdentity)
        workspace.lockSelected()
        #expect(await workspace.unlock(password: "synthetic-password"))
        workspace.setMarkdown("锁定前的延迟回调", from: unlockedToken)
        #expect(workspace.markdown == "合成正文")
        workspace.setMarkdown("新的合法编辑", from: try #require(workspace.editorIdentity))
        #expect(workspace.markdown == "新的合法编辑")
    }

    @Test func lockingPendingEditSavesCiphertextAndReopensExactDraft() async throws {
        let (store, workspace) = try await fixture()
        let id = try #require(workspace.selectedID)
        #expect(await workspace.encrypt(password: "synthetic-password"))
        #expect(await workspace.unlock(password: "synthetic-password"))
        let marker = "SEC005-合成私密补记"
        workspace.markdown = marker
        workspace.lockSelected()
        #expect(workspace.markdown.isEmpty)
        #expect(await workspace.flush())
        let saved = try await store.load(id: id)
        #expect(try DiaryFileCodec.encode(saved).range(of: Data(marker.utf8)) == nil)
        let reopened = DiaryWorkspace(store: store)
        await reopened.open()
        #expect(reopened.isLocked)
        #expect(await reopened.unlock(password: "synthetic-password"))
        #expect(reopened.markdown == marker)
        reopened.filter.titleQuery = marker
        #expect(reopened.visibleEntries.isEmpty)
    }

    private func fixture() async throws -> (MemoryStore, DiaryWorkspace) {
        let store = MemoryStore()
        _ = try await store.save(document(), expectedRevision: nil)
        let workspace = DiaryWorkspace(store: store)
        await workspace.open()
        return (store, workspace)
    }

    private func document(title: String = "合成标题") -> DiaryDocument {
        DiaryDocument(metadata: DiaryMetadata(title: title), content: .plain(DiaryPayload(markdown: "合成正文")))
    }
}
