import Darwin
import Foundation

public actor DiaryRepository: DiaryStore {
    public let directory: URL
    private let writer: any DiaryFileWriting

    public init(directory: URL, writer: any DiaryFileWriting = AtomicDiaryWriter()) {
        self.directory = directory
        self.writer = writer
    }

    public func index() throws -> DiaryIndex {
        try prepareDirectory()
        let lock = try acquireWriterLock()
        defer {
            flock(lock, LOCK_UN)
            close(lock)
        }
        try prepareDirectory(trashDirectory)
        let active = try scan(directory)
        let trash = try scan(trashDirectory)
        return DiaryIndex(
            entries: active.entries, trashedEntries: trash.entries, issues: active.issues + trash.issues)
    }

    private func scan(_ folder: URL) throws -> DiaryIndex {
        let urls = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: .skipsHiddenFiles
        ).filter { $0.lastPathComponent.hasSuffix(".diary.json") }
        var summaries: [DiarySummary] = []
        var issues: [DiaryLoadIssue] = []
        for url in urls {
            do {
                let document = try read(url)
                guard
                    url.resolvingSymlinksInPath()
                        == fileURL(id: document.metadata.id, in: folder).resolvingSymlinksInPath()
                else { throw DiaryStoreError.invalidFile }
                summaries.append(document.summary)
            } catch {
                let preserved = preserveUnreadableFile(url, error: error)
                issues.append(
                    DiaryLoadIssue(
                        fileName: url.lastPathComponent,
                        reason: error.localizedDescription, preservedAt: preserved))
            }
        }
        summaries.sort(by: DiarySummary.newestFirst)
        return DiaryIndex(entries: summaries, issues: issues)
    }

    public func load(id: UUID) throws -> DiaryDocument {
        let document = try read(fileURL(id: id))
        guard document.metadata.id == id else { throw DiaryStoreError.invalidFile }
        return document
    }

    public func save(_ document: DiaryDocument, expectedRevision: UInt64?) throws -> DiaryDocument {
        try document.validate()
        try prepareDirectory()
        let lock = try acquireWriterLock()
        defer {
            flock(lock, LOCK_UN)
            close(lock)
        }

        let destination = fileURL(id: document.metadata.id)
        if FileManager.default.fileExists(atPath: destination.path) {
            let previous = try read(destination)
            guard previous.metadata.revision == expectedRevision,
                previous.metadata.createdAt == document.metadata.createdAt,
                previous.metadata.day == document.metadata.day,
                previous.metadata.timeZoneID == document.metadata.timeZoneID
            else {
                throw DiaryStoreError.conflict
            }
        } else if expectedRevision != nil
            || FileManager.default.fileExists(
                atPath: fileURL(id: document.metadata.id, in: trashDirectory).path)
        {
            throw DiaryStoreError.conflict
        }
        guard expectedRevision != UInt64.max else { throw DiaryStoreError.conflict }
        var committed = document
        committed.metadata.revision = (expectedRevision ?? 0) + 1
        try writer.write(DiaryFileCodec.encode(committed), to: destination)
        return committed
    }

    var trashDirectory: URL { directory.appendingPathComponent("Trash", isDirectory: true) }

    func prepareDirectory(_ folder: URL? = nil) throws {
        let folder = folder ?? directory
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let values = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw DiaryStoreError.invalidFile
        }
    }

    func fileURL(id: UUID, in folder: URL? = nil) -> URL {
        (folder ?? directory).appendingPathComponent("\(id.uuidString.lowercased()).diary.json")
    }

    func read(_ url: URL) throws -> DiaryDocument {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw DiaryStoreError.invalidFile
        }
        guard (values.fileSize ?? 0) <= DiaryFileCodec.maximumFileBytes else {
            throw DiaryStoreError.tooLarge
        }
        return try DiaryFileCodec.decode(Data(contentsOf: url, options: .mappedIfSafe))
    }

    func acquireWriterLock() throws -> Int32 {
        let descriptor = open(
            directory.appendingPathComponent(".writer.lock").path,
            O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw DiaryStoreError.libraryBusy
        }
        return descriptor
    }

    private func preserveUnreadableFile(_ url: URL, error: Error) -> URL {
        if case DiaryStoreError.unsupportedVersion = error { return url }
        // Preserve links and I/O failures in place; quarantine only malformed/invalid data.
        guard error is DecodingError || error as? DiaryStoreError == .invalidDocument else { return url }
        let quarantine = url.deletingLastPathComponent().appendingPathComponent(
            "Quarantine", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: quarantine, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            let target = quarantine.appendingPathComponent("\(UUID().uuidString)-\(url.lastPathComponent)")
            try FileManager.default.moveItem(at: url, to: target)
            return target
        } catch {
            return url
        }
    }
}
