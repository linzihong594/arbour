import DiaryCore
import DiaryState
import Foundation
import Testing

@MainActor
struct BiometricSessionTests {
    @Test func enablesUnlocksAndReopensUsingTheProtectedDataKey() async throws {
        let (store, access, session) = try await fixture()
        #expect(await session.enableTouchID())
        #expect(session.isBiometricEnabled)
        session.lock()
        #expect(await session.unlockWithTouchID())
        #expect(session.text == "合成私密正文")
        session.editMarkdown("指纹路径解锁后的新补记")
        #expect(await session.autosave.flush())
        let saved = try await store.load(id: session.document.metadata.id)
        #expect(try DiaryFileCodec.encode(saved).range(of: Data("新补记".utf8)) == nil)
        let reopened = DiarySession(document: saved, store: store, biometrics: access)
        await reopened.refreshBiometricStatus()
        #expect(reopened.isBiometricEnabled && reopened.isLocked)
        #expect(await reopened.unlockWithTouchID())
        #expect(reopened.text == "指纹路径解锁后的新补记")
        #expect(await reopened.disableTouchID())
        #expect(await access.contains(id: saved.metadata.id) == false)
    }

    @Test func failedEnrollmentKeepsPasswordUnlockAndCiphertextUnchanged() async throws {
        let (_, access, session) = try await fixture()
        let before = session.document
        await access.failEnrollment()
        #expect(await session.enableTouchID() == false)
        #expect(!session.isBiometricEnabled && session.document == before)
        session.lock()
        #expect(await session.unlock(password: "synthetic-password"))
        #expect(session.text == "合成私密正文")
    }

    @Test func wrongReleasedKeyCannotUnlockAndPasswordStillWorks() async throws {
        let (_, access, session) = try await fixture()
        #expect(await session.enableTouchID())
        await access.replaceKey(id: session.document.metadata.id)
        session.lock()
        #expect(await session.unlockWithTouchID() == false)
        #expect(session.isLocked && session.text == nil)
        #expect(await session.unlock(password: "synthetic-password"))
        #expect(session.text == "合成私密正文")
    }

    @Test func lockingDuringAuthenticationRejectsTheLateResult() async throws {
        let (_, access, session) = try await fixture()
        #expect(await session.enableTouchID())
        session.lock()
        await access.delayRead()
        let operation = Task { await session.unlockWithTouchID() }
        for _ in 0..<1000 {
            if await access.isReading { break }
            await Task.yield()
        }
        #expect(await access.isReading)
        session.lock()
        #expect(await operation.value == false)
        #expect(session.isLocked && session.text == nil)
    }

    private func fixture() async throws -> (MemoryStore, SyntheticBiometricAccess, DiarySession) {
        let store = MemoryStore()
        let access = SyntheticBiometricAccess()
        let document = DiaryDocument(
            metadata: DiaryMetadata(title: "合成日记"),
            content: .plain(DiaryPayload(markdown: "合成私密正文")))
        let saved = try await store.save(document, expectedRevision: nil)
        let session = DiarySession(document: saved, store: store, biometrics: access)
        #expect(await session.encrypt(password: "synthetic-password"))
        #expect(await session.unlock(password: "synthetic-password"))
        return (store, access, session)
    }
}

private actor SyntheticBiometricAccess: DiaryBiometricAccess {
    nonisolated let unavailabilityReason: String? = nil
    private var keys: [UUID: Data] = [:]
    private var fails = false
    private var slow = false
    private(set) var isReading = false
    func contains(id: UUID) -> Bool { keys[id] != nil }
    func store(_ key: Data, id: UUID) throws {
        if fails { throw CocoaError(.fileWriteNoPermission) }
        keys[id] = key
    }
    @MainActor func load(id: UUID) async throws -> Data { try await read(id: id) }
    private func read(id: UUID) async throws -> Data {
        isReading = true
        if slow { try await Task.sleep(for: .milliseconds(80)) }
        return try #require(keys[id])
    }
    func remove(id: UUID) { keys[id] = nil }
    nonisolated func cancel() {}
    func failEnrollment() { fails = true }
    func delayRead() { slow = true }
    func replaceKey(id: UUID) { keys[id] = Data(repeating: 0, count: 32) }
}
