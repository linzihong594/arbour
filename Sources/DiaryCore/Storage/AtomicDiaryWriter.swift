import Darwin
import Foundation

public protocol DiaryFileWriting: Sendable {
    func write(_ data: Data, to destination: URL) throws
}

public struct AtomicDiaryWriter: DiaryFileWriting {
    public init() {}

    public func write(_ data: Data, to destination: URL) throws {
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".pending-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: staging) }
        try data.write(to: staging, options: .withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: staging.path)
        let handle = try FileHandle(forWritingTo: staging)
        do {
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
        // Same-directory rename publishes a complete file or leaves the old file intact.
        guard Darwin.rename(staging.path, destination.path) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }
}
