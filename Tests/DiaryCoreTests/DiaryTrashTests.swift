import Darwin
import DiaryCore
import Foundation
import Testing

struct DiaryTrashTests {
    @Test(arguments: [false, true])
    func moveAndRestorePreserveExactBytesAndRejectStaleSave(encrypted: Bool) async throws {
        let fixture = TrashFixture()
        defer { fixture.cleanup() }
        var draft = fixture.document()
        if encrypted {
            draft.content = .encrypted(
                try DiaryCryptor.encrypt(
                    DiaryPayload(markdown: "合成私密正文"), password: "synthetic-password",
                    diaryID: draft.metadata.id
                ).document)
        }
        let saved = try await fixture.store.save(draft, expectedRevision: nil)
        let original = try Data(contentsOf: fixture.file(saved))
        #expect(try await fixture.store.trash(id: saved.metadata.id, expectedRevision: 1) == saved.summary)
        let reopened = DiaryRepository(directory: fixture.url)
        let index = try await reopened.index()
        #expect(index.entries.isEmpty)
        #expect(index.trashedEntries == [saved.summary])
        #expect(try Data(contentsOf: fixture.file(saved, trashed: true)) == original)
        await #expect(throws: DiaryStoreError.conflict) {
            try await reopened.save(saved, expectedRevision: 1)
        }
        await #expect(throws: DiaryStoreError.conflict) {
            try await reopened.save(draft, expectedRevision: nil)
        }
        let restored = try await reopened.restore(id: saved.metadata.id, expectedRevision: 1)
        #expect(restored == saved)
        #expect(try Data(contentsOf: fixture.file(saved)) == original)
        #expect(try await reopened.index().trashedEntries.isEmpty)
    }

    @Test func staleMoveAndExistingTrashCannotOverwrite() async throws {
        let fixture = TrashFixture()
        defer { fixture.cleanup() }
        let saved = try await fixture.store.save(fixture.document(), expectedRevision: nil)
        await #expect(throws: DiaryStoreError.conflict) {
            try await fixture.store.trash(id: saved.metadata.id, expectedRevision: 0)
        }
        _ = try await fixture.store.index()
        let collision = Data("unrelated existing bytes".utf8)
        try collision.write(to: fixture.file(saved, trashed: true))
        await #expect(throws: DiaryStoreError.conflict) {
            try await fixture.store.trash(id: saved.metadata.id, expectedRevision: 1)
        }
        #expect(try await fixture.store.load(id: saved.metadata.id) == saved)
        #expect(try Data(contentsOf: fixture.file(saved, trashed: true)) == collision)
    }

    @Test func restoreCollisionPreservesBothCopies() async throws {
        let fixture = TrashFixture()
        defer { fixture.cleanup() }
        let saved = try await fixture.store.save(fixture.document(), expectedRevision: nil)
        _ = try await fixture.store.trash(id: saved.metadata.id, expectedRevision: 1)
        var other = saved
        other.metadata.title = "外部同 ID 文件"
        try DiaryFileCodec.encode(other).write(to: fixture.file(saved))
        await #expect(throws: DiaryStoreError.conflict) {
            try await fixture.store.restore(id: saved.metadata.id, expectedRevision: 1)
        }
        #expect(try DiaryFileCodec.decode(Data(contentsOf: fixture.file(saved, trashed: true))) == saved)
        #expect(try await fixture.store.load(id: saved.metadata.id) == other)
    }

    @Test func trashCorruptionIsPreservedAndFutureVersionStaysInPlace() async throws {
        let fixture = TrashFixture()
        defer { fixture.cleanup() }
        _ = try await fixture.store.index()
        let trash = fixture.url.appendingPathComponent("Trash")
        let future = trash.appendingPathComponent("future.diary.json")
        let broken = trash.appendingPathComponent("broken.diary.json")
        let bytes = Data("{invalid".utf8)
        try bytes.write(to: broken)
        try Data("{\"schemaVersion\":999}".utf8).write(to: future)
        let index = try await fixture.store.index()
        #expect(index.issues.count == 2)
        let issue = try #require(index.issues.first { $0.fileName == broken.lastPathComponent })
        #expect(try Data(contentsOf: issue.preservedAt) == bytes)
        #expect(FileManager.default.fileExists(atPath: future.path))
    }

    @Test func linkedTrashDirectoryIsRejected() async throws {
        let fixture = TrashFixture()
        defer { fixture.cleanup() }
        let saved = try await fixture.store.save(fixture.document(), expectedRevision: nil)
        let outside = fixture.url.appendingPathComponent("Outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(
            at: fixture.url.appendingPathComponent("Trash"), withDestinationURL: outside)
        await #expect(throws: DiaryStoreError.invalidFile) {
            try await fixture.store.trash(id: saved.metadata.id, expectedRevision: 1)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }

    @Test func moveRespectsAnotherProcessLock() async throws {
        let fixture = TrashFixture()
        defer { fixture.cleanup() }
        let saved = try await fixture.store.save(fixture.document(), expectedRevision: nil)
        let descriptor = open(fixture.url.appendingPathComponent(".writer.lock").path, O_RDWR)
        #expect(descriptor >= 0)
        defer { close(descriptor) }
        #expect(flock(descriptor, LOCK_EX | LOCK_NB) == 0)
        await #expect(throws: DiaryStoreError.libraryBusy) {
            try await fixture.store.trash(id: saved.metadata.id, expectedRevision: 1)
        }
        #expect(try await fixture.store.load(id: saved.metadata.id) == saved)
    }
}

private struct TrashFixture {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("diary-trash-\(UUID())")
    var store: DiaryRepository { DiaryRepository(directory: url) }
    func document() -> DiaryDocument {
        DiaryDocument(metadata: DiaryMetadata(title: "合成日记"), content: .plain(DiaryPayload(markdown: "原文")))
    }
    func file(_ document: DiaryDocument, trashed: Bool = false) -> URL {
        (trashed ? url.appendingPathComponent("Trash") : url)
            .appendingPathComponent("\(document.metadata.id.uuidString.lowercased()).diary.json")
    }
    func cleanup() { try? FileManager.default.removeItem(at: url) }
}
