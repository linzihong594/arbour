import DiaryCore
import DiaryState
import Foundation
import Testing

@MainActor
struct LocationSessionTests {
    private let sample = DiaryLocation(
        latitude: 31.2304, longitude: 121.4737, horizontalAccuracy: 12,
        capturedAt: Date(timeIntervalSince1970: 1_700_000_000), source: .current, label: "上海")

    @Test func attachesSyntheticLocationToPlainDiaryAndPersists() async throws {
        let store = MemoryStore()
        let saved = try await store.save(plainDocument(), expectedRevision: nil)
        let session = DiarySession(document: saved, store: store)
        let provider = StubLocationProvider(result: .success(sample))

        #expect(await session.attachCurrentLocation(using: provider))
        #expect(session.location == sample)
        #expect(await session.autosave.flush())

        let stored = try await store.load(id: saved.metadata.id)
        #expect(stored.schemaVersion == 2)
        guard case .plain(let payload) = stored.content else {
            Issue.record("Expected plain payload")
            return
        }
        #expect(payload.location == sample)
    }

    @Test func deniedOrTimedOutRequestKeepsDiaryUnchanged() async throws {
        let store = MemoryStore()
        let saved = try await store.save(plainDocument(), expectedRevision: nil)
        let session = DiarySession(document: saved, store: store)
        let provider = StubLocationProvider(result: .failure(.timeout))

        #expect(await session.attachCurrentLocation(using: provider) == false)
        #expect(session.location == nil)
        #expect(session.errorMessage != nil)
        #expect(await session.autosave.flush())
        #expect(try await store.load(id: saved.metadata.id) == saved)
        #expect(await store.writeCount == 1)
    }

    @Test func encryptedDiaryKeepsLocationInsideCiphertext() async throws {
        let store = MemoryStore()
        let saved = try await store.save(plainDocument(), expectedRevision: nil)
        let session = DiarySession(document: saved, store: store)
        #expect(await session.encrypt(password: "location-test-password"))
        #expect(await session.unlock(password: "location-test-password"))
        let provider = StubLocationProvider(result: .success(sample))
        #expect(await session.attachCurrentLocation(using: provider))
        #expect(await session.autosave.flush())

        let stored = try await store.load(id: saved.metadata.id)
        #expect(stored.schemaVersion == 2)
        guard case .encrypted(let encrypted) = stored.content else {
            Issue.record("Expected ciphertext")
            return
        }
        #expect(try DiaryFileCodec.encode(stored).range(of: Data("上海".utf8)) == nil)
        let unlocked = try DiaryCryptor.unlock(encrypted, password: "location-test-password")
        #expect(unlocked.payload.location == sample)
    }

    @Test func lockedSessionRejectsLocationChanges() async throws {
        let store = MemoryStore()
        let base = plainDocument()
        let encrypted = try DiaryCryptor.encrypt(
            DiaryPayload(markdown: "私密正文"), password: "location-test-password",
            diaryID: base.metadata.id)
        var document = base
        document.content = .encrypted(encrypted.document)
        let saved = try await store.save(document, expectedRevision: nil)
        let session = DiarySession(document: saved, store: store)
        let provider = StubLocationProvider(result: .success(sample))

        #expect(session.isLocked && session.location == nil)
        #expect(session.setLocation(sample) == false)
        #expect(await session.attachCurrentLocation(using: provider) == false)
        #expect(provider.requestCount == 0)
    }

    @Test func clearingLocationRemovesItButKeepsExtendedVersion() async throws {
        let store = MemoryStore()
        let saved = try await store.save(plainDocument(), expectedRevision: nil)
        let session = DiarySession(document: saved, store: store)
        #expect(session.setLocation(sample))
        #expect(session.setLocation(nil))
        #expect(session.location == nil)
        #expect(await session.autosave.flush())
        let stored = try await store.load(id: saved.metadata.id)
        #expect(stored.schemaVersion == 2)
        guard case .plain(let payload) = stored.content else {
            Issue.record("Expected plain payload")
            return
        }
        #expect(payload.location == nil)
    }

    private func plainDocument() -> DiaryDocument {
        DiaryDocument(
            metadata: DiaryMetadata(title: "合成位置日记"),
            content: .plain(DiaryPayload(markdown: "带位置的正文")))
    }
}

@MainActor
private final class StubLocationProvider: DiaryLocationProviding {
    let result: Result<DiaryLocation, DiaryLocationRequestError>
    private(set) var requestCount = 0

    init(result: Result<DiaryLocation, DiaryLocationRequestError>) {
        self.result = result
    }

    func requestCurrentLocation() async throws -> DiaryLocation {
        requestCount += 1
        switch result {
        case .success(let location): return location
        case .failure(let error): throw error
        }
    }
}
