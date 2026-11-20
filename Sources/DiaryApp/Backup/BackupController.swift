import DiaryCore
import DiaryPlatform
import Foundation
import Observation

enum BackupStatus: Equatable {
    case idle
    case working(String)
    case localComplete(entryCount: Int, date: Date, cloud: BackupCloudState, snapshotURL: URL)
    case restored(directory: String, activeCount: Int, trashedCount: Int)
    case failed(message: String, retryable: Bool)

    var isWorking: Bool {
        if case .working = self { return true }
        return false
    }

    var label: String {
        switch self {
        case .idle: "尚未创建快照"
        case .working(let label): label
        case .localComplete(let count, let date, let cloud, _):
            "已写入 \(count) 个文件，\(date.formatted(date: .abbreviated, time: .standard))；\(cloud.label)"
        case .restored(let directory, let active, let trashed):
            "已恢复到 \(directory)：\(active) 篇备份内日记、\(trashed) 篇废纸篓日记。"
        case .failed(let message, _): message
        }
    }

    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

/// Owns the directory grant and the snapshot/restore workflow for the app window.
@MainActor
@Observable
final class BackupController {
    static let bookmarkDefaultsKey = "preview.backupDirectoryBookmark"
    static let autoBackupDefaultsKey = "preview.autoBackupEnabled"

    private(set) var status: BackupStatus = .idle
    private(set) var snapshots: [BackupSnapshotSummary] = []
    private(set) var isBusy = false
    private(set) var directoryName: String?
    private(set) var cloudState: BackupCloudState = .unknown
    private(set) var hasDirectory = false
    let isValidation: Bool

    var autoBackupEnabled: Bool {
        didSet { defaults.set(autoBackupEnabled, forKey: Self.autoBackupDefaultsKey) }
    }

    private let libraryURL: URL
    private let defaults: UserDefaults
    private var autoTask: Task<Void, Never>?
    private var didLoad = false

    init(libraryURL: URL, isValidation: Bool, defaults: UserDefaults = .standard) {
        self.libraryURL = libraryURL
        self.isValidation = isValidation
        self.defaults = defaults
        autoBackupEnabled =
            (defaults.object(forKey: Self.autoBackupDefaultsKey) as? Bool) ?? true
    }

    func load() async {
        guard !didLoad else { return }
        didLoad = true
        guard let bookmark = defaults.data(forKey: Self.bookmarkDefaultsKey) else { return }
        hasDirectory = true
        do {
            let loaded = try await Task.detached {
                let directory = try BackupDirectory(bookmark: bookmark).resolve()
                let accessing = directory.url.startAccessingSecurityScopedResource()
                defer { if accessing { directory.url.stopAccessingSecurityScopedResource() } }
                return (
                    directory.url, directory.isStale,
                    BackupService.listSnapshots(in: directory.url),
                    BackupCloudInspector.state(of: BackupService.snapshotsRoot(for: directory.url))
                )
            }.value
            directoryName = loaded.0.lastPathComponent
            guard !loaded.1 else {
                hasDirectory = false
                status = .failed(message: "备份目录授权已过期，请重新选择。", retryable: false)
                return
            }
            snapshots = loaded.2
            cloudState = loaded.3
        } catch {
            hasDirectory = false
            status = .failed(message: error.localizedDescription, retryable: true)
        }
    }

    func grantDirectory(_ url: URL) {
        guard !isBusy else { return }
        isBusy = true
        status = .working("正在验证目录授权…")
        Task {
            do {
                let granted = try await Task.detached {
                    let directory = try BackupDirectory(url: url)
                    let access = try directory.verifyAccess()
                    return (
                        directory.bookmark, access.url.lastPathComponent,
                        BackupService.listSnapshots(in: access.url),
                        BackupCloudInspector.state(of: BackupService.snapshotsRoot(for: access.url))
                    )
                }.value
                defaults.set(granted.0, forKey: Self.bookmarkDefaultsKey)
                hasDirectory = true
                directoryName = granted.1
                snapshots = granted.2
                cloudState = granted.3
                status = .idle
            } catch {
                status = .failed(message: error.localizedDescription, retryable: true)
            }
            isBusy = false
        }
    }

    func createSnapshot(automatically: Bool = false) {
        guard hasDirectory else {
            status = .failed(message: "请先选择备份目录。", retryable: false)
            return
        }
        guard let bookmark = defaults.data(forKey: Self.bookmarkDefaultsKey) else {
            hasDirectory = false
            status = .failed(message: "备份目录授权已丢失，请重新选择。", retryable: false)
            return
        }
        guard !isBusy else { return }
        isBusy = true
        status = .working(automatically ? "正在自动备份…" : "正在创建快照…")
        let libraryURL = libraryURL
        let version = Self.appVersion
        Task {
            do {
                let created = try await Task.detached {
                    let directory = try BackupDirectory(bookmark: bookmark).resolve()
                    guard !directory.isStale else {
                        throw BackupError.directoryUnavailable
                    }
                    let accessing = directory.url.startAccessingSecurityScopedResource()
                    defer { if accessing { directory.url.stopAccessingSecurityScopedResource() } }
                    let snapshot = try BackupService.createSnapshot(
                        libraryURL: libraryURL, backupRoot: directory.url, appVersion: version)
                    return (
                        snapshot,
                        BackupCloudInspector.state(
                            of: BackupService.snapshotsRoot(for: directory.url)),
                        BackupService.listSnapshots(in: directory.url)
                    )
                }.value
                snapshots = created.2
                cloudState = created.1
                status = .localComplete(
                    entryCount: created.0.manifest.entries.count,
                    date: created.0.manifest.createdAt, cloud: created.1,
                    snapshotURL: created.0.url)
            } catch {
                status = .failed(
                    message: error.localizedDescription,
                    retryable: (error as? BackupError)?.isRetryable ?? true)
            }
            isBusy = false
        }
    }

    func restore(snapshot: BackupSnapshotSummary, to targetDirectory: URL) {
        guard !isBusy else { return }
        guard let bookmark = defaults.data(forKey: Self.bookmarkDefaultsKey) else {
            status = .failed(message: "备份目录授权已丢失，请重新选择。", retryable: false)
            return
        }
        isBusy = true
        status = .working("正在校验快照并恢复到所选目录…")
        Task {
            do {
                let result = try await Task.detached {
                    let directory = try BackupDirectory(bookmark: bookmark).resolve()
                    guard !directory.isStale else {
                        throw BackupError.directoryUnavailable
                    }
                    let accessing = directory.url.startAccessingSecurityScopedResource()
                    defer { if accessing { directory.url.stopAccessingSecurityScopedResource() } }
                    return try BackupService.restoreSnapshot(
                        at: snapshot.url, into: targetDirectory)
                }.value
                status = .restored(
                    directory: result.directory.path,
                    activeCount: result.activeCount, trashedCount: result.trashedCount)
                snapshots = await refreshList(bookmark: bookmark)
            } catch {
                status = .failed(
                    message: error.localizedDescription,
                    retryable: (error as? BackupError)?.isRetryable ?? true)
            }
            isBusy = false
        }
    }

    func refreshSnapshots() {
        guard let bookmark = defaults.data(forKey: Self.bookmarkDefaultsKey) else { return }
        Task {
            snapshots = await refreshList(bookmark: bookmark)
        }
    }

    /// Called after the editor reports a saved entry, so a quiet period produces one snapshot.
    func noteSaveCompleted() {
        guard autoBackupEnabled, hasDirectory, !isValidation else { return }
        autoTask?.cancel()
        autoTask = Task {
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled else { return }
            createSnapshot(automatically: true)
        }
    }

    private func refreshList(bookmark: Data) async -> [BackupSnapshotSummary] {
        (try? await Task.detached {
            let directory = try BackupDirectory(bookmark: bookmark).resolve()
            let accessing = directory.url.startAccessingSecurityScopedResource()
            defer { if accessing { directory.url.stopAccessingSecurityScopedResource() } }
            return BackupService.listSnapshots(in: directory.url)
        }.value) ?? []
    }

    private static var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (short, build) {
        case (let short?, let build?): return "\(short) (\(build))"
        case (let short?, nil): return short
        case (nil, let build?): return build
        default: return "unknown"
        }
    }
}
