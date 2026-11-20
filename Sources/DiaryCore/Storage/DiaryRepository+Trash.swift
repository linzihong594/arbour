import Darwin
import Foundation

extension DiaryRepository {
    public func trash(id: UUID, expectedRevision: UInt64) throws -> DiarySummary {
        try move(id: id, expectedRevision: expectedRevision, restoring: false).summary
    }

    public func restore(id: UUID, expectedRevision: UInt64) throws -> DiaryDocument {
        try move(id: id, expectedRevision: expectedRevision, restoring: true)
    }

    private func move(id: UUID, expectedRevision: UInt64, restoring: Bool) throws -> DiaryDocument {
        try prepareDirectory()
        let lock = try acquireWriterLock()
        defer {
            flock(lock, LOCK_UN)
            close(lock)
        }
        try prepareDirectory(trashDirectory)
        let source = fileURL(id: id, in: restoring ? trashDirectory : directory)
        let destination = fileURL(id: id, in: restoring ? directory : trashDirectory)
        guard FileManager.default.fileExists(atPath: source.path) else { throw DiaryStoreError.conflict }
        let document = try read(source)
        guard document.metadata.id == id, document.metadata.revision == expectedRevision else {
            throw DiaryStoreError.conflict
        }
        // Same-volume rename preserves the exact container and refuses any existing target.
        guard renamex_np(source.path, destination.path, UInt32(RENAME_EXCL)) == 0 else {
            if errno == EEXIST { throw DiaryStoreError.conflict }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        return document
    }
}
