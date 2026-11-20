import Darwin
import Foundation

public enum MarkdownExportError: LocalizedError {
    case locked
    case invalidDestination

    public var errorDescription: String? {
        switch self {
        case .locked: "请先解锁这篇日记，再导出正文。"
        case .invalidDestination: "请选择一个新的 .md 文件；已有文件不会被覆盖。"
        }
    }
}

public enum MarkdownExport {
    /// Write only to the user-selected new file, without a plaintext staging/cache file.
    public static func write(_ markdown: String, to destination: URL) throws {
        guard destination.isFileURL, destination.pathExtension.lowercased() == "md" else {
            throw MarkdownExportError.invalidDestination
        }
        let descriptor = open(destination.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else {
            if errno == EEXIST { throw MarkdownExportError.invalidDestination }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: Data(markdown.utf8))
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    public static func suggestedName(for metadata: DiaryMetadata) -> String {
        let forbidden = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/\\:"))
        let title = metadata.title.components(separatedBy: forbidden).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let shortTitle = String((title.isEmpty ? "日记" : title).prefix(40))
        return "\(metadata.day)-\(shortTitle).md"
    }
}
