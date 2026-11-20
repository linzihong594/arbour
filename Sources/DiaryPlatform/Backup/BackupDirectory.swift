import Foundation

/// Stores only the user's directory grant. It does not imply a cloud upload succeeded.
public struct BackupDirectory: Sendable {
    public let bookmark: Data

    public init(url: URL) throws {
        bookmark = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    public init(bookmark: Data) {
        self.bookmark = bookmark
    }

    public func resolve() throws -> (url: URL, isStale: Bool) {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return (url, isStale)
    }

    /// Uses a uniquely named synthetic probe, then removes it even when verification fails.
    public func verifyAccess() throws -> DirectoryAccessResult {
        let resolved = try resolve()
        guard !resolved.isStale else {
            throw PlatformError.message("目录授权已过期，请重新选择备份目录。")
        }
        let accessing = resolved.url.startAccessingSecurityScopedResource()
        defer { if accessing { resolved.url.stopAccessingSecurityScopedResource() } }

        let probe = resolved.url.appendingPathComponent(".mac-diary-probe-\(UUID().uuidString).tmp")
        let contents = Data("mac-diary synthetic directory probe".utf8)
        try contents.write(to: probe, options: .withoutOverwriting)
        do {
            guard try Data(contentsOf: probe) == contents else {
                throw PlatformError.message("目录读写校验未通过。")
            }
            let isCloudItem =
                try probe.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem == true
            try FileManager.default.removeItem(at: probe)
            return DirectoryAccessResult(url: resolved.url, isCloudItem: isCloudItem)
        } catch {
            try? FileManager.default.removeItem(at: probe)
            throw error
        }
    }
}

public struct DirectoryAccessResult: Sendable {
    public let url: URL
    public let isCloudItem: Bool
}
