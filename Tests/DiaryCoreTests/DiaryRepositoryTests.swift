import DiaryCore
import Foundation
import Testing

struct DiaryRepositoryTests {
    @Test func createEditAndReopenPreserveMarkdownAndIdentity() async throws {
        let fixture = try LibraryFixture()
        defer { fixture.cleanup() }
        var document = try await fixture.store.save(fixture.document(), expectedRevision: nil)
        let id = document.metadata.id
        document.metadata.title = "修改后的标题"
        document.content = .plain(DiaryPayload(markdown: "## 中文 🌿\n\n| A | B |\n|---|---|\n| 一 | 二 |"))
        document = try await fixture.store.save(document, expectedRevision: 1)
        let reopened = DiaryRepository(directory: fixture.url)
        #expect(try await reopened.load(id: id) == document)
        #expect(try await reopened.index().entries.map(\.id) == [id])
        #expect(document.metadata.revision == 2)
    }

    @Test func sameDayDiariesHaveDifferentFiles() async throws {
        let fixture = try LibraryFixture()
        defer { fixture.cleanup() }
        _ = try await fixture.store.save(fixture.document(), expectedRevision: nil)
        _ = try await fixture.store.save(fixture.document(), expectedRevision: nil)
        #expect(try await fixture.store.index().entries.count == 2)
    }

    @Test func staleRevisionCannotOverwriteAnotherWriter() async throws {
        let fixture = try LibraryFixture()
        defer { fixture.cleanup() }
        let original = try await fixture.store.save(fixture.document(), expectedRevision: nil)
        var changed = original
        changed.metadata.title = "另一个窗口的版本"
        let latest = try await DiaryRepository(directory: fixture.url).save(changed, expectedRevision: 1)
        await #expect(throws: DiaryStoreError.conflict) {
            try await fixture.store.save(original, expectedRevision: 1)
        }
        #expect(try await fixture.store.load(id: original.metadata.id) == latest)
    }

    @Test func failureBeforeCommitPreservesOldFile() async throws {
        let fixture = try LibraryFixture()
        defer { fixture.cleanup() }
        var document = try await fixture.store.save(fixture.document(), expectedRevision: nil)
        let original = try await fixture.store.load(id: document.metadata.id)
        document.content = .plain(DiaryPayload(markdown: "尚未提交的新正文"))
        let failing = DiaryRepository(directory: fixture.url, writer: FailingWriter())
        await #expect(throws: CocoaError.self) { try await failing.save(document, expectedRevision: 1) }
        #expect(try await fixture.store.load(id: document.metadata.id) == original)
    }

    @Test func corruptFileIsQuarantinedAndValidFileStillLoads() async throws {
        let fixture = try LibraryFixture()
        defer { fixture.cleanup() }
        let saved = try await fixture.store.save(fixture.document(), expectedRevision: nil)
        let bad = fixture.url.appendingPathComponent("broken.diary.json")
        let bytes = Data("{broken-json".utf8)
        try bytes.write(to: bad)
        let index = try await fixture.store.index()
        #expect(index.entries.map(\.id) == [saved.metadata.id])
        let issue = try #require(index.issues.first)
        #expect(issue.preservedAt.deletingLastPathComponent().lastPathComponent == "Quarantine")
        #expect(try Data(contentsOf: issue.preservedAt) == bytes)
    }

    @Test func futureVersionIsPreservedInPlace() async throws {
        let fixture = try LibraryFixture()
        defer { fixture.cleanup() }
        _ = try await fixture.store.index()
        let url = fixture.url.appendingPathComponent("future.diary.json")
        let bytes = Data("{\"schemaVersion\":999,\"futureContent\":true}".utf8)
        try bytes.write(to: url)
        let index = try await fixture.store.index()
        #expect(index.entries.isEmpty)
        #expect(index.issues.first?.preservedAt.resolvingSymlinksInPath() == url.resolvingSymlinksInPath())
        #expect(try Data(contentsOf: url) == bytes)
    }

    @Test func encryptedFileNeverContainsBodyAndReopensLocked() async throws {
        let fixture = try LibraryFixture()
        defer { fixture.cleanup() }
        var document = fixture.document()
        let payload = DiaryPayload(markdown: "M2-合成私密正文-不可出现在文件中")
        let encrypted = try DiaryCryptor.encrypt(
            payload, password: "synthetic-test-password", diaryID: document.metadata.id)
        document.content = .encrypted(encrypted.document)
        let saved = try await fixture.store.save(document, expectedRevision: nil)
        let file = fixture.url.appendingPathComponent(
            "\(saved.metadata.id.uuidString.lowercased()).diary.json")
        #expect(try Data(contentsOf: file).range(of: Data(payload.markdown.utf8)) == nil)
        let loaded = try await DiaryRepository(directory: fixture.url).load(id: saved.metadata.id)
        guard case .encrypted(let content) = loaded.content else {
            Issue.record("Expected ciphertext")
            return
        }
        #expect(try DiaryCryptor.unlock(content, password: "synthetic-test-password").payload == payload)
    }

    @Test func naturalDaySurvivesTimeZoneChange() throws {
        let zone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let metadata = DiaryMetadata(title: "自然日", date: date, timeZone: zone)
        let document = DiaryDocument(metadata: metadata, content: .plain(DiaryPayload(markdown: "")))
        let decoded = try DiaryFileCodec.decode(DiaryFileCodec.encode(document))
        #expect(decoded.metadata.day == metadata.day)
        #expect(decoded.metadata.timeZoneID == "Asia/Shanghai")
        #expect(decoded.metadata.createdAt == metadata.createdAt)
    }

    @Test func stagedFileIsCleanedAndPermissionsArePrivate() async throws {
        let fixture = try LibraryFixture()
        defer { fixture.cleanup() }
        let document = try await fixture.store.save(fixture.document(), expectedRevision: nil)
        let names = try FileManager.default.contentsOfDirectory(atPath: fixture.url.path)
        #expect(!names.contains { $0.hasPrefix(".pending-") })
        let name = "\(document.metadata.id.uuidString.lowercased()).diary.json"
        let permissions =
            try FileManager.default.attributesOfItem(atPath: fixture.url.appendingPathComponent(name).path)[
                .posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)
    }
}

private struct FailingWriter: DiaryFileWriting {
    func write(_ data: Data, to destination: URL) throws { throw CocoaError(.fileWriteOutOfSpace) }
}

private struct LibraryFixture {
    let url: URL
    let store: DiaryRepository

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mac-diary-test-\(UUID().uuidString)")
        store = DiaryRepository(directory: url)
    }

    func document() -> DiaryDocument {
        DiaryDocument(metadata: DiaryMetadata(title: "合成日记"), content: .plain(DiaryPayload(markdown: "测试正文")))
    }

    func cleanup() { try? FileManager.default.removeItem(at: url) }
}
