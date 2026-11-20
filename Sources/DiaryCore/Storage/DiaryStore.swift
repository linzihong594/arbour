import Foundation

public protocol DiaryStore: Sendable {
    func index() async throws -> DiaryIndex
    func load(id: UUID) async throws -> DiaryDocument
    func save(_ document: DiaryDocument, expectedRevision: UInt64?) async throws -> DiaryDocument
    func trash(id: UUID, expectedRevision: UInt64) async throws -> DiarySummary
    func restore(id: UUID, expectedRevision: UInt64) async throws -> DiaryDocument
}

public struct DiaryIndex: Sendable {
    public let entries: [DiarySummary]
    public let trashedEntries: [DiarySummary]
    public let issues: [DiaryLoadIssue]

    public init(
        entries: [DiarySummary], trashedEntries: [DiarySummary] = [], issues: [DiaryLoadIssue] = []
    ) {
        self.entries = entries
        self.trashedEntries = trashedEntries
        self.issues = issues
    }
}

public struct DiaryLoadIssue: Identifiable, Sendable {
    public let fileName: String
    public let reason: String
    public let preservedAt: URL
    public var id: String { fileName }
}

public enum DiaryStoreError: LocalizedError, Equatable {
    case unsupportedVersion(Int)
    case invalidDocument
    case tooLarge
    case conflict
    case invalidFile
    case libraryBusy

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): "此日记使用较新的文件格式（\(version)），原文件已保留。"
        case .invalidDocument: "日记文件的日期或内容格式无效。"
        case .tooLarge: "日记文件超过当前版本支持的大小，请保留原文件。"
        case .conflict: "磁盘上的日记已被其他窗口或程序修改。当前编辑保留在内存中，暂不覆盖原文件。"
        case .invalidFile: "日记文件不是可读取的普通文件，原文件已保留。"
        case .libraryBusy: "日记库正在被另一个进程写入，请稍后重试。"
        }
    }
}
