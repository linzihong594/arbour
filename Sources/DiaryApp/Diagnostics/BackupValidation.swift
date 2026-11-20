import CryptoKit
import DiaryCore
import DiaryPlatform
import Foundation

/// Cross-process validation: create a snapshot from a synthetic library, verify it, restore it into
/// an isolated directory, and record the evidence without starting any user-facing workflow.
enum BackupValidation {
    static func run(
        libraryURL: URL, backupRoot: URL, restoreRoot: URL, output: URL
    ) async throws {
        let created = try await Task.detached {
            try BackupService.createSnapshot(
                libraryURL: libraryURL, backupRoot: backupRoot, appVersion: "validation")
        }.value
        let manifest = try await Task.detached { try BackupService.verifySnapshot(at: created.url) }
            .value
        let restored = try await Task.detached {
            try BackupService.restoreSnapshot(at: created.url, into: restoreRoot)
        }.value

        let fileManager = FileManager.default
        var encryptedByteIdentical = true
        var trashByteIdentical = true
        var manifestLeaksBody = false
        var schemaVersions = Set<Int>()
        for entry in manifest.entries {
            schemaVersions.insert(entry.schemaVersion)
            if entry.isEncrypted {
                let source = libraryPath(for: entry.path, in: libraryURL)
                let copy = created.url.appendingPathComponent(entry.path)
                if (try? Data(contentsOf: source)) != (try? Data(contentsOf: copy)) {
                    encryptedByteIdentical = false
                }
            }
            if entry.path.hasPrefix("Trash/") {
                let source = libraryPath(for: entry.path, in: libraryURL)
                let restoredFile = libraryPath(for: entry.path, in: restoreRoot)
                if (try? Data(contentsOf: source)) != (try? Data(contentsOf: restoredFile)) {
                    trashByteIdentical = false
                }
            }
        }

        let manifestText =
            (try? String(
                contentsOf: created.url.appendingPathComponent(BackupService.manifestFileName),
                encoding: .utf8)) ?? ""
        for marker in ["合成私密日记", "M2 合成正文", "合成普通日记", "合成废纸篓日记"] {
            if manifestText.contains(marker) { manifestLeaksBody = true }
        }

        let repository = DiaryRepository(directory: restoreRoot)
        let index = try await repository.index()
        let completeMarkerExists = fileManager.fileExists(
            atPath: created.url.appendingPathComponent(BackupService.completeMarkerFileName).path)

        let report: [String: Any] = [
            "createdAt": ISO8601DateFormatter().string(from: .now),
            "snapshotPath": created.url.path,
            "manifestEntries": manifest.entries.count,
            "activeEntries": manifest.activeCount,
            "trashedEntries": manifest.trashedCount,
            "totalBytes": manifest.totalBytes,
            "schemaVersions": schemaVersions.sorted(),
            "checksumsVerified": true,
            "completeMarkerExists": completeMarkerExists,
            "restoredDirectory": restoreRoot.path,
            "restoredActiveCount": restored.activeCount,
            "restoredTrashedCount": restored.trashedCount,
            "libraryIndexActive": index.entries.count,
            "libraryIndexTrashed": index.trashedEntries.count,
            "libraryIssues": index.issues.count,
            "encryptedContainerByteIdentical": encryptedByteIdentical,
            "trashContainerByteIdentical": trashByteIdentical,
            "manifestLeaksBodyText": manifestLeaksBody,
            "cloudState": BackupCloudInspector.state(
                of: BackupService.snapshotsRoot(for: backupRoot)
            ).rawValue,
            "localWriteDone": true,
        ]
        try JSONSerialization.data(
            withJSONObject: report, options: [.prettyPrinted, .sortedKeys]
        ).write(to: output, options: .atomic)
    }

    private static func libraryPath(for manifestPath: String, in directory: URL) -> URL {
        if manifestPath.hasPrefix("Entries/") {
            return directory.appendingPathComponent(String(manifestPath.dropFirst("Entries/".count)))
        }
        return directory.appendingPathComponent(
            "Trash/" + String(manifestPath.dropFirst("Trash/".count)))
    }
}
