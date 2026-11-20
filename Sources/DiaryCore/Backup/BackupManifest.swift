import Foundation

/// Describes one file inside a backup snapshot. Paths are relative to the snapshot directory.
public struct BackupEntry: Codable, Equatable, Sendable {
    public var path: String
    public var uuid: UUID
    public var isEncrypted: Bool
    public var schemaVersion: Int
    public var byteCount: Int
    public var sha256: String

    public init(
        path: String, uuid: UUID, isEncrypted: Bool, schemaVersion: Int, byteCount: Int,
        sha256: String
    ) {
        self.path = path
        self.uuid = uuid
        self.isEncrypted = isEncrypted
        self.schemaVersion = schemaVersion
        self.byteCount = byteCount
        self.sha256 = sha256
    }

    public func validate() throws {
        guard path.hasPrefix("Entries/") || path.hasPrefix("Trash/") else {
            throw BackupError.invalidManifest("条目路径必须位于 Entries 或 Trash 中。")
        }
        let name = String(path.dropFirst(path.hasPrefix("Entries/") ? 8 : 6))
        guard !name.isEmpty, !name.contains("/"), !name.contains(".."),
            name.hasSuffix(".diary.json"),
            name == "\(uuid.uuidString.lowercased()).diary.json"
        else {
            throw BackupError.invalidManifest("条目路径与 UUID 不一致。")
        }
        guard byteCount >= 0, byteCount <= DiaryFileCodec.maximumFileBytes else {
            throw BackupError.invalidManifest("备份条目大小超出限制。")
        }
        guard sha256.count == 64, sha256.allSatisfy({ $0.isHexDigit }) else {
            throw BackupError.invalidManifest("备份条目缺少有效校验值。")
        }
        guard (DiarySchema.earliestVersion...DiarySchema.currentVersion).contains(schemaVersion)
        else { throw BackupError.invalidManifest("备份条目包含不支持的格式版本。") }
    }
}

/// The manifest is the only metadata written next to the copied containers. It never contains a title or body.
public struct BackupManifest: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var snapshotID: UUID
    public var createdAt: Date
    public var appVersion: String
    public var entries: [BackupEntry]
    public var totalBytes: Int

    public init(
        formatVersion: Int = BackupManifest.currentFormatVersion, snapshotID: UUID,
        createdAt: Date, appVersion: String, entries: [BackupEntry]
    ) {
        self.formatVersion = formatVersion
        self.snapshotID = snapshotID
        self.createdAt = createdAt
        self.appVersion = appVersion
        self.entries = entries.sorted { $0.path < $1.path }
        totalBytes = self.entries.reduce(0) { $0 + $1.byteCount }
    }

    public func validate() throws {
        guard formatVersion == Self.currentFormatVersion else {
            throw BackupError.unsupportedFormat(formatVersion)
        }
        guard totalBytes >= 0,
            totalBytes == entries.reduce(0, { $0 + $1.byteCount })
        else { throw BackupError.invalidManifest("备份清单的总大小不一致。") }
        var paths = Set<String>()
        var ids = Set<UUID>()
        for entry in entries {
            try entry.validate()
            guard paths.insert(entry.path).inserted else {
                throw BackupError.invalidManifest("备份清单包含重复路径。")
            }
            guard ids.insert(entry.uuid).inserted else {
                throw BackupError.invalidManifest("备份清单包含重复日记 UUID。")
            }
        }
    }

    public var activeCount: Int { entries.filter { $0.path.hasPrefix("Entries/") }.count }
    public var trashedCount: Int { entries.filter { $0.path.hasPrefix("Trash/") }.count }
}

public struct BackupSnapshot: Sendable {
    public let url: URL
    public let manifest: BackupManifest

    public init(url: URL, manifest: BackupManifest) {
        self.url = url
        self.manifest = manifest
    }
}

public struct BackupSnapshotSummary: Identifiable, Equatable, Sendable {
    public var url: URL
    public var manifest: BackupManifest

    public var id: UUID { manifest.snapshotID }
    public init(url: URL, manifest: BackupManifest) {
        self.url = url
        self.manifest = manifest
    }
}

public struct BackupRestoreResult: Sendable {
    public let directory: URL
    public let manifest: BackupManifest
    public let activeCount: Int
    public let trashedCount: Int
}

public enum BackupError: Error, Equatable, LocalizedError, Sendable {
    case directoryUnavailable
    case libraryBusy
    case incompleteSnapshot
    case unsupportedFormat(Int)
    case invalidManifest(String)
    case missingEntry(String)
    case unexpectedEntry(String)
    case checksumMismatch(String)
    case destinationConflict(String)
    case invalidSource(String)
    case ioFailure(String)

    public var errorDescription: String? {
        switch self {
        case .directoryUnavailable: "备份目录不可用，请重新选择目录后再试。"
        case .libraryBusy: "日记库正在写入，请稍后重试备份。"
        case .incompleteSnapshot: "备份缺少完成标记，不能恢复。"
        case .unsupportedFormat(let version): "备份格式版本 \(version) 不受支持。"
        case .invalidManifest(let reason): "备份清单无效：\(reason)"
        case .missingEntry(let path): "备份缺少文件：\(path)"
        case .unexpectedEntry(let path): "备份包含清单外文件：\(path)"
        case .checksumMismatch(let path): "备份文件校验失败：\(path)"
        case .destinationConflict(let reason): "目标目录不能用于恢复：\(reason)"
        case .invalidSource(let reason): "日记库中有无法备份的文件：\(reason)"
        case .ioFailure(let reason): "备份操作失败：\(reason)"
        }
    }

    public var isRetryable: Bool {
        switch self {
        case .libraryBusy, .directoryUnavailable, .ioFailure: true
        default: false
        }
    }
}
