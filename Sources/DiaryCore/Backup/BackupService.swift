import CryptoKit
import Darwin
import Foundation

/// Creates, verifies, restores, and prunes encrypted-at-rest diary snapshots.
///
/// A snapshot is staged inside the backup directory and moved into place only after every file has
/// been copied, hashed, and recorded, followed by a `COMPLETE` marker. Restores verify the same
/// manifest before writing anything into an isolated target directory.
public enum BackupService {
    public static let snapshotsDirectoryName = "MacDiarySnapshots"
    public static let defaultRetention = 5
    public static let manifestFileName = "manifest.json"
    public static let completeMarkerFileName = "COMPLETE"

    public static func snapshotsRoot(for backupRoot: URL) -> URL {
        backupRoot.appendingPathComponent(snapshotsDirectoryName, isDirectory: true)
    }

    // MARK: - Create

    public static func createSnapshot(
        libraryURL: URL, backupRoot: URL, appVersion: String, now: Date = .now,
        retention: Int = defaultRetention
    ) throws -> BackupSnapshot {
        guard retention >= 1 else {
            throw BackupError.invalidSource("快照保留数量必须至少为 1。")
        }
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard
            fileManager.fileExists(atPath: libraryURL.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else { throw BackupError.directoryUnavailable }

        let lock = try acquireLibraryLock(in: libraryURL)
        defer { releaseLibraryLock(lock) }

        do {
            let snapshotsRoot = snapshotsRoot(for: backupRoot)
            try createDirectory(backupRoot)
            try createDirectory(snapshotsRoot)

            let snapshotID = UUID()
            let finalURL = snapshotsRoot.appendingPathComponent(
                "snapshot-\(timestamp(now))-\(snapshotID.uuidString.prefix(8).lowercased())",
                isDirectory: true
            )
            guard !fileManager.fileExists(atPath: finalURL.path) else {
                throw BackupError.ioFailure("同名快照已存在。")
            }
            let pendingURL = snapshotsRoot.appendingPathComponent(
                ".pending-\(snapshotID.uuidString.lowercased())", isDirectory: true
            )
            try? fileManager.removeItem(at: pendingURL)

            do {
                try createDirectory(pendingURL)
                try createDirectory(pendingURL.appendingPathComponent("Entries", isDirectory: true))
                try createDirectory(pendingURL.appendingPathComponent("Trash", isDirectory: true))

                var entries: [BackupEntry] = []
                for section in ["Entries", "Trash"] {
                    entries += try copy(
                        section: section, from: libraryURL, to: pendingURL, snapshotID: snapshotID
                    )
                }

                let manifest = BackupManifest(
                    snapshotID: snapshotID, createdAt: now, appVersion: appVersion, entries: entries
                )
                try manifest.validate()
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .millisecondsSince1970
                try write(
                    try encoder.encode(manifest),
                    to: pendingURL.appendingPathComponent(manifestFileName),
                    permissions: 0o600
                )
                try write(
                    Data("\(snapshotID.uuidString)\n".utf8),
                    to: pendingURL.appendingPathComponent(completeMarkerFileName),
                    permissions: 0o600
                )

                try fileManager.moveItem(at: pendingURL, to: finalURL)
                try? pruneSnapshots(in: snapshotsRoot, keeping: retention)
                return BackupSnapshot(url: finalURL, manifest: manifest)
            } catch {
                try? fileManager.removeItem(at: pendingURL)
                throw normalize(error)
            }
        } catch {
            throw normalize(error)
        }
    }

    private static func copy(
        section: String, from libraryURL: URL, to pendingURL: URL, snapshotID: UUID
    ) throws -> [BackupEntry] {
        let sourceDirectory =
            section == "Entries"
            ? libraryURL : libraryURL.appendingPathComponent("Trash", isDirectory: true)
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sourceDirectory.path, isDirectory: &isDirectory) else {
            return []
        }
        guard isDirectory.boolValue else {
            throw BackupError.invalidSource("\(section) 不是目录。")
        }

        let destinationDirectory = pendingURL.appendingPathComponent(section, isDirectory: true)
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        let urls = try fileManager.contentsOfDirectory(
            at: sourceDirectory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ).sorted { $0.lastPathComponent < $1.lastPathComponent }

        var entries: [BackupEntry] = []
        for url in urls {
            let values = try url.resourceValues(forKeys: Set(keys))
            guard values.isSymbolicLink != true else {
                throw BackupError.invalidSource("\(section)/\(url.lastPathComponent) 是符号链接。")
            }
            guard values.isRegularFile == true else { continue }
            let name = url.lastPathComponent
            guard name.hasSuffix(".diary.json") else {
                throw BackupError.invalidSource("\(section)/\(name) 不是日记文件。")
            }
            if let fileSize = values.fileSize, fileSize > DiaryFileCodec.maximumFileBytes {
                throw BackupError.invalidSource("\(section)/\(name) 超出大小限制。")
            }
            let data = try Data(contentsOf: url)
            guard data.count <= DiaryFileCodec.maximumFileBytes else {
                throw BackupError.invalidSource("\(section)/\(name) 超出大小限制。")
            }
            let document: DiaryDocument
            do {
                document = try DiaryFileCodec.decode(data)
            } catch {
                throw BackupError.invalidSource("\(section)/\(name) 无法解析或版本不受支持。")
            }
            guard name == "\(document.metadata.id.uuidString.lowercased()).diary.json" else {
                throw BackupError.invalidSource("\(section)/\(name) 与日记 UUID 不一致。")
            }
            try write(
                data, to: destinationDirectory.appendingPathComponent(name), permissions: 0o600
            )
            entries.append(
                BackupEntry(
                    path: "\(section)/\(name)", uuid: document.metadata.id,
                    isEncrypted: document.content.isEncrypted,
                    schemaVersion: document.schemaVersion, byteCount: data.count,
                    sha256: sha256Hex(data)
                )
            )
        }
        return entries
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    // MARK: - Verify

    public static func verifySnapshot(at snapshotURL: URL) throws -> BackupManifest {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard
            fileManager.fileExists(atPath: snapshotURL.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            throw BackupError.directoryUnavailable
        }

        let manifestURL = snapshotURL.appendingPathComponent(manifestFileName)
        guard let manifestData = try? Data(contentsOf: manifestURL) else {
            throw BackupError.invalidManifest("快照缺少 manifest.json。")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let manifest: BackupManifest
        do {
            manifest = try decoder.decode(BackupManifest.self, from: manifestData)
        } catch {
            throw BackupError.invalidManifest("manifest.json 无法解析。")
        }
        try manifest.validate()

        let completeURL = snapshotURL.appendingPathComponent(completeMarkerFileName)
        guard
            let complete = try? String(contentsOf: completeURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            complete.lowercased() == manifest.snapshotID.uuidString.lowercased()
        else { throw BackupError.incompleteSnapshot }

        var actualFiles: [String: URL] = [:]
        for section in ["Entries", "Trash"] {
            let directory = snapshotURL.appendingPathComponent(section, isDirectory: true)
            var sectionIsDirectory: ObjCBool = false
            guard
                fileManager.fileExists(atPath: directory.path, isDirectory: &sectionIsDirectory),
                sectionIsDirectory.boolValue
            else { throw BackupError.incompleteSnapshot }
            let urls = try fileManager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                options: []
            )
            for url in urls {
                let values = try url.resourceValues(
                    forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
                )
                guard values.isSymbolicLink != true, values.isRegularFile == true else {
                    throw BackupError.unexpectedEntry("\(section)/\(url.lastPathComponent)")
                }
                let name = url.lastPathComponent
                guard name.hasSuffix(".diary.json") else {
                    throw BackupError.unexpectedEntry("\(section)/\(name)")
                }
                actualFiles["\(section)/\(name)"] = url
            }
        }

        let expectedPaths = Set(manifest.entries.map(\.path))
        let actualPaths = Set(actualFiles.keys)
        if let missing = expectedPaths.subtracting(actualPaths).sorted().first {
            throw BackupError.missingEntry(missing)
        }
        if let unexpected = actualPaths.subtracting(expectedPaths).sorted().first {
            throw BackupError.unexpectedEntry(unexpected)
        }

        for entry in manifest.entries {
            guard let url = actualFiles[entry.path] else {
                throw BackupError.missingEntry(entry.path)
            }
            let data = try Data(contentsOf: url)
            guard data.count == entry.byteCount, sha256Hex(data) == entry.sha256 else {
                throw BackupError.checksumMismatch(entry.path)
            }
            let document: DiaryDocument
            do {
                document = try DiaryFileCodec.decode(data)
            } catch DiaryStoreError.unsupportedVersion(let version) {
                throw BackupError.unsupportedFormat(version)
            } catch {
                throw BackupError.checksumMismatch(entry.path)
            }
            guard
                document.metadata.id == entry.uuid,
                document.schemaVersion == entry.schemaVersion,
                document.content.isEncrypted == entry.isEncrypted
            else {
                throw BackupError.invalidManifest("快照内容与清单不一致：\(entry.path)")
            }
        }
        return manifest
    }

    // MARK: - Restore

    public static func restoreSnapshot(at snapshotURL: URL, into targetDirectory: URL) throws
        -> BackupRestoreResult
    {
        let manifest = try verifySnapshot(at: snapshotURL)
        let fileManager = FileManager.default
        var targetIsDirectory: ObjCBool = false
        if fileManager.fileExists(
            atPath: targetDirectory.path, isDirectory: &targetIsDirectory
        ) {
            guard targetIsDirectory.boolValue else {
                throw BackupError.destinationConflict("目标路径不是目录。")
            }
        } else {
            try createDirectory(targetDirectory)
        }

        let trashTarget = targetDirectory.appendingPathComponent("Trash", isDirectory: true)
        try makeReplaceableEmptyDirectory(trashTarget)
        let existing = try fileManager.contentsOfDirectory(
            at: targetDirectory, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for url in existing where url.lastPathComponent != "Trash" {
            if url.lastPathComponent.hasSuffix(".diary.json") {
                throw BackupError.destinationConflict("目标目录已包含日记文件。")
            }
        }

        let pendingURL = targetDirectory.appendingPathComponent(
            ".restore-\(UUID().uuidString.lowercased())", isDirectory: true
        )
        try? fileManager.removeItem(at: pendingURL)
        let pendingTrash = pendingURL.appendingPathComponent("Trash", isDirectory: true)
        var moved: [URL] = []
        do {
            try createDirectory(pendingURL)
            try createDirectory(pendingTrash)

            for entry in manifest.entries {
                let relativePath: String
                if entry.path.hasPrefix("Entries/") {
                    relativePath = String(entry.path.dropFirst("Entries/".count))
                } else {
                    relativePath = "Trash/" + String(entry.path.dropFirst("Trash/".count))
                }
                let data = try Data(contentsOf: snapshotURL.appendingPathComponent(entry.path))
                guard data.count == entry.byteCount, sha256Hex(data) == entry.sha256 else {
                    throw BackupError.checksumMismatch(entry.path)
                }
                try write(
                    data, to: pendingURL.appendingPathComponent(relativePath), permissions: 0o600)
            }

            try createDirectory(trashTarget)
            for entry in manifest.entries where entry.path.hasPrefix("Trash/") {
                let name = String(entry.path.dropFirst("Trash/".count))
                let destination = trashTarget.appendingPathComponent(name)
                try fileManager.moveItem(at: pendingTrash.appendingPathComponent(name), to: destination)
                moved.append(destination)
            }
            for entry in manifest.entries where entry.path.hasPrefix("Entries/") {
                let name = String(entry.path.dropFirst("Entries/".count))
                let destination = targetDirectory.appendingPathComponent(name)
                try fileManager.moveItem(at: pendingURL.appendingPathComponent(name), to: destination)
                moved.append(destination)
            }
            try? fileManager.removeItem(at: pendingURL)
            return BackupRestoreResult(
                directory: targetDirectory, manifest: manifest,
                activeCount: manifest.activeCount, trashedCount: manifest.trashedCount
            )
        } catch {
            for url in moved { try? fileManager.removeItem(at: url) }
            try? fileManager.removeItem(at: pendingURL)
            throw normalize(error)
        }
    }

    // MARK: - Listing and retention

    public static func listSnapshots(in backupRoot: URL) -> [BackupSnapshotSummary] {
        let root = snapshotsRoot(for: backupRoot)
        let fileManager = FileManager.default
        guard
            let names = try? fileManager.contentsOfDirectory(atPath: root.path)
        else { return [] }

        var summaries: [BackupSnapshotSummary] = []
        for name in names where name.hasPrefix("snapshot-") && !name.hasPrefix(".") {
            let url = root.appendingPathComponent(name, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard
                fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                isDirectory.boolValue
            else { continue }
            guard let manifest = try? readManifest(at: url) else { continue }
            guard
                let complete = try? String(
                    contentsOf: url.appendingPathComponent(completeMarkerFileName), encoding: .utf8
                ).trimmingCharacters(in: .whitespacesAndNewlines),
                complete.lowercased() == manifest.snapshotID.uuidString.lowercased()
            else { continue }
            summaries.append(BackupSnapshotSummary(url: url, manifest: manifest))
        }
        return summaries.sorted { $0.manifest.createdAt > $1.manifest.createdAt }
    }

    private static func readManifest(at snapshotURL: URL) throws -> BackupManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let manifest = try decoder.decode(
            BackupManifest.self,
            from: Data(contentsOf: snapshotURL.appendingPathComponent(manifestFileName))
        )
        try manifest.validate()
        return manifest
    }

    private static func pruneSnapshots(in snapshotsRoot: URL, keeping retention: Int) throws {
        let fileManager = FileManager.default
        let summaries = listSnapshots(in: snapshotsRoot.deletingLastPathComponent())
        guard summaries.count > retention else { return }
        for summary in summaries.dropFirst(retention) {
            try? fileManager.removeItem(at: summary.url)
        }
    }

    // MARK: - Helpers

    private static func createDirectory(_ url: URL) throws {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw BackupError.ioFailure("\(url.lastPathComponent) 不是目录。")
            }
            return
        }
        try FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    private static func makeReplaceableEmptyDirectory(_ url: URL) throws {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }
        guard isDirectory.boolValue else {
            throw BackupError.destinationConflict("\(url.lastPathComponent) 已存在且不是目录。")
        }
        let contents = try fileManager.contentsOfDirectory(atPath: url.path)
        guard contents.isEmpty else {
            throw BackupError.destinationConflict("\(url.lastPathComponent) 已存在且非空。")
        }
        try fileManager.removeItem(at: url)
    }

    private static func write(_ data: Data, to url: URL, permissions: Int) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: permissions], ofItemAtPath: url.path
        )
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func normalize(_ error: Error) -> BackupError {
        if let backupError = error as? BackupError { return backupError }
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == EACCES || nsError.code == EPERM {
            return .directoryUnavailable
        }
        return .ioFailure(nsError.localizedDescription)
    }

    private static func acquireLibraryLock(in libraryURL: URL) throws -> Int32 {
        let lockURL = libraryURL.appendingPathComponent(".writer.lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw BackupError.directoryUnavailable }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw BackupError.libraryBusy
        }
        return descriptor
    }

    private static func releaseLibraryLock(_ descriptor: Int32) {
        guard descriptor >= 0 else { return }
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}
