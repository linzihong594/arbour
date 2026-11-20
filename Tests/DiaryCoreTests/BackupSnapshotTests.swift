import CryptoKit
import Darwin
import DiaryCore
import Foundation
import Testing

struct BackupSnapshotTests {
    private let password = "backup-test-password"
    private let plainID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let privateID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    private let trashedID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!

    @Test func snapshotRecordsManifestWithoutBodyText() async throws {
        let area = try TemporaryArea()
        let library = try await area.makeLibrary(
            password: password, plainID: plainID, privateID: privateID, trashedID: trashedID)
        let snapshot = try BackupService.createSnapshot(
            libraryURL: library, backupRoot: try area.directory(), appVersion: "test")

        #expect(snapshot.manifest.entries.count == 3)
        #expect(snapshot.manifest.activeCount == 2)
        #expect(snapshot.manifest.trashedCount == 1)
        #expect(
            FileManager.default.fileExists(
                atPath: snapshot.url.appendingPathComponent(BackupService.completeMarkerFileName)
                    .path))

        let manifestText = try String(
            contentsOf: snapshot.url.appendingPathComponent(BackupService.manifestFileName),
            encoding: .utf8)
        #expect(!manifestText.contains("合成普通日记"))
        #expect(!manifestText.contains("合成私密日记"))
        #expect(!manifestText.contains("只用于备份与恢复验证"))

        let manifest = try BackupService.verifySnapshot(at: snapshot.url)
        #expect(manifest.entries.count == 3)
        #expect(manifest.entries.contains { $0.schemaVersion == 3 })

        let encrypted = try #require(manifest.entries.first { $0.isEncrypted })
        let source = libraryPath(for: encrypted.path, in: library)
        let copy = snapshot.url.appendingPathComponent(encrypted.path)
        #expect(try Data(contentsOf: source) == (try Data(contentsOf: copy)))
    }

    @Test func retentionKeepsNewestCompletedSnapshots() async throws {
        let area = try TemporaryArea()
        let library = try await area.makeLibrary(
            password: password, plainID: plainID, privateID: privateID, trashedID: trashedID)
        let backupRoot = try area.directory()
        var created: [BackupSnapshot] = []
        for offset in 0..<3 {
            created.append(
                try BackupService.createSnapshot(
                    libraryURL: library, backupRoot: backupRoot, appVersion: "test",
                    now: Date(timeIntervalSince1970: 1_800_000_000 + Double(offset)),
                    retention: 2))
        }
        let snapshots = BackupService.listSnapshots(in: backupRoot)
        #expect(snapshots.count == 2)
        #expect(Set(snapshots.map(\.id)) == Set(created.suffix(2).map(\.manifest.snapshotID)))
        #expect(!FileManager.default.fileExists(atPath: created[0].url.path))
        if let oldestKept = snapshots.last {
            #expect(throws: Never.self) { try BackupService.verifySnapshot(at: oldestKept.url) }
        }
    }

    @Test func verifyRejectsTamperedFile() async throws {
        let area = try TemporaryArea()
        let snapshot = try await makeSnapshot(in: area)
        let tampered = try copySnapshot(snapshot.url, named: "tampered", in: area)
        let entry = try #require(
            BackupService.verifySnapshot(at: tampered).entries.first { !$0.isEncrypted })
        let url = tampered.appendingPathComponent(entry.path)
        var data = try Data(contentsOf: url)
        data[data.startIndex] ^= 0x01
        try data.write(to: url, options: .atomic)

        expectBackupError(
            matching: { if case .checksumMismatch = $0 { true } else { false } },
            operation: {
                _ = try BackupService.verifySnapshot(at: tampered)
            })
    }

    @Test func verifyRejectsMissingCompletionMarker() async throws {
        let area = try TemporaryArea()
        let snapshot = try await makeSnapshot(in: area)
        let incomplete = try copySnapshot(snapshot.url, named: "incomplete", in: area)
        try FileManager.default.removeItem(
            at: incomplete.appendingPathComponent(BackupService.completeMarkerFileName))
        expectBackupError(
            matching: { $0 == .incompleteSnapshot },
            operation: {
                _ = try BackupService.verifySnapshot(at: incomplete)
            })
    }

    @Test func verifyRejectsUnexpectedFile() async throws {
        let area = try TemporaryArea()
        let snapshot = try await makeSnapshot(in: area)
        let unexpected = try copySnapshot(snapshot.url, named: "unexpected", in: area)
        let extra = unexpected.appendingPathComponent(
            "Entries/\(UUID().uuidString.lowercased()).diary.json")
        try Data("{}".utf8).write(to: extra)
        expectBackupError(
            matching: { if case .unexpectedEntry = $0 { true } else { false } },
            operation: {
                _ = try BackupService.verifySnapshot(at: unexpected)
            })
    }

    @Test func restorePreservesBytesTrashAndEncryptedContainers() async throws {
        let area = try TemporaryArea()
        let library = try await area.makeLibrary(
            password: password, plainID: plainID, privateID: privateID, trashedID: trashedID)
        let snapshot = try BackupService.createSnapshot(
            libraryURL: library, backupRoot: try area.directory(), appVersion: "test")
        let target = try area.directory()
        let restored = try BackupService.restoreSnapshot(at: snapshot.url, into: target)

        #expect(restored.activeCount == 2)
        #expect(restored.trashedCount == 1)
        for entry in snapshot.manifest.entries {
            #expect(
                try Data(contentsOf: libraryPath(for: entry.path, in: library))
                    == (try Data(contentsOf: libraryPath(for: entry.path, in: target))))
        }

        let repository = DiaryRepository(directory: target)
        let index = try await repository.index()
        #expect(index.entries.count == 2)
        #expect(index.trashedEntries.count == 1)
        #expect(index.issues.isEmpty)

        let encrypted = try await repository.load(id: privateID)
        guard case .encrypted(let container) = encrypted.content else {
            Issue.record("expected encrypted container after restore")
            return
        }
        #expect(
            try DiaryCryptor.unlock(container, password: password).payload.markdown
                .contains("只用于备份与恢复验证"))
    }

    @Test func restoreRefusesNonEmptyTargetWithoutOverwriting() async throws {
        let area = try TemporaryArea()
        let snapshot = try await makeSnapshot(in: area)
        let target = try area.directory()
        let existing = target.appendingPathComponent("existing.diary.json")
        try Data("existing".utf8).write(to: existing)

        expectBackupError(
            matching: { if case .destinationConflict = $0 { true } else { false } },
            operation: {
                _ = try BackupService.restoreSnapshot(at: snapshot.url, into: target)
            })
        #expect(try String(contentsOf: existing, encoding: .utf8) == "existing")
    }

    @Test func libraryLockFailureIsRetryable() async throws {
        let area = try TemporaryArea()
        let library = try await area.makeLibrary(
            password: password, plainID: plainID, privateID: privateID, trashedID: trashedID)
        let backupRoot = try area.directory()
        let lockPath = library.appendingPathComponent(".writer.lock").path
        let descriptor = open(lockPath, O_CREAT | O_RDWR, 0o600)
        #expect(descriptor >= 0)
        #expect(flock(descriptor, LOCK_EX | LOCK_NB) == 0)
        defer {
            flock(descriptor, LOCK_UN)
            close(descriptor)
        }
        do {
            _ = try BackupService.createSnapshot(
                libraryURL: library, backupRoot: backupRoot, appVersion: "test")
            Issue.record("expected libraryBusy")
        } catch let error as BackupError {
            #expect(error == .libraryBusy)
            #expect(error.isRetryable)
        } catch {
            Issue.record("expected libraryBusy, got \(error)")
        }
    }

    // MARK: - Helpers

    private func libraryPath(for manifestPath: String, in library: URL) -> URL {
        if manifestPath.hasPrefix("Entries/") {
            return library.appendingPathComponent(String(manifestPath.dropFirst("Entries/".count)))
        }
        return library.appendingPathComponent(
            "Trash/" + String(manifestPath.dropFirst("Trash/".count)))
    }

    private func makeSnapshot(in area: TemporaryArea) async throws -> BackupSnapshot {
        let library = try await area.makeLibrary(
            password: password, plainID: plainID, privateID: privateID, trashedID: trashedID)
        return try BackupService.createSnapshot(
            libraryURL: library, backupRoot: try area.directory(), appVersion: "test")
    }

    private func copySnapshot(_ snapshot: URL, named name: String, in area: TemporaryArea) throws
        -> URL
    {
        let destination = try area.directory().appendingPathComponent(name, isDirectory: true)
        try FileManager.default.copyItem(at: snapshot, to: destination)
        return destination
    }

    private func expectBackupError(
        matching: (BackupError) -> Bool, operation: () throws -> Void,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        do {
            try operation()
            Issue.record("expected a backup error", sourceLocation: sourceLocation)
        } catch let error as BackupError {
            #expect(matching(error), sourceLocation: sourceLocation)
        } catch {
            Issue.record("expected a backup error, got \(error)", sourceLocation: sourceLocation)
        }
    }
}

private final class TemporaryArea {
    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mac-diary-backup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func directory() throws -> URL {
        let url = root.appendingPathComponent("Directory-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func makeLibrary(password: String, plainID: UUID, privateID: UUID, trashedID: UUID) async throws
        -> URL
    {
        let directory = try directory()
        let store = DiaryRepository(directory: directory)
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        for (id, title, encrypted) in [
            (plainID, "合成普通日记", false), (privateID, "合成私密日记", true),
        ] {
            let metadata = DiaryMetadata(
                id: id, title: title, date: base, timeZone: TimeZone(identifier: "Asia/Shanghai")!)
            let payload = DiaryPayload(
                markdown: "## \(title)\n\n这段只用于备份与恢复验证。\n")
            let content: DiaryContent =
                encrypted
                ? .encrypted(
                    try DiaryCryptor.encrypt(payload, password: password, diaryID: id).document)
                : .plain(payload)
            var document = DiaryDocument(metadata: metadata, content: content)
            document.schemaVersion = encrypted ? 2 : 1
            _ = try await store.save(document, expectedRevision: nil)
        }

        let location = DiaryLocation(
            latitude: 31.2304, longitude: 121.4737, horizontalAccuracy: 0,
            capturedAt: base, source: .manual, label: "合成地点")
        let weather = DiaryWeather(
            temperatureCelsius: 21.5, weatherCode: 2, fetchedAt: base,
            source: "Open-Meteo", timeZoneID: "Asia/Shanghai")
        var trashed = DiaryDocument(
            metadata: DiaryMetadata(
                id: trashedID, title: "合成带位置天气日记", date: base,
                timeZone: TimeZone(identifier: "Asia/Shanghai")!),
            content: .plain(
                DiaryPayload(
                    markdown: "## 合成废纸篓正文\n\n这一段只用于备份与恢复验证。\n",
                    location: location, weather: weather)))
        trashed.schemaVersion = 3
        _ = try await store.save(trashed, expectedRevision: nil)
        let index = try await store.index()
        let saved = try #require(index.entries.first { $0.id == trashedID })
        _ = try await store.trash(id: trashedID, expectedRevision: saved.metadata.revision)
        return directory
    }
}
