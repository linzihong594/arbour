import Foundation

public struct DiaryDocument: Codable, Equatable, Sendable {
    public var schemaVersion: Int = 1
    public var metadata: DiaryMetadata
    public var content: DiaryContent

    public init(metadata: DiaryMetadata, content: DiaryContent) {
        self.metadata = metadata
        self.content = content
    }

    public var summary: DiarySummary {
        DiarySummary(metadata: metadata, isEncrypted: content.isEncrypted)
    }

    public func validate() throws {
        guard (DiarySchema.earliestVersion...DiarySchema.currentVersion).contains(schemaVersion)
        else { throw DiaryStoreError.unsupportedVersion(schemaVersion) }
        guard metadata.day.count == 10, metadata.diaryDate != nil,
            metadata.updatedAt >= metadata.createdAt,
            metadata.title.utf8.count <= 4096
        else { throw DiaryStoreError.invalidDocument }
        switch content {
        case .plain(let payload):
            try payload.validate()
            guard schemaVersion >= payload.requiredSchemaVersion else {
                throw DiaryStoreError.invalidDocument
            }
            guard payload.markdown.utf8.count <= 8 * 1024 * 1024 else { throw DiaryStoreError.tooLarge }
        case .encrypted(let encrypted):
            guard encrypted.diaryID == metadata.id else { throw DiaryStoreError.invalidDocument }
            try DiaryCryptor.validateFormat(encrypted)
        }
    }
}

public enum DiaryContent: Equatable, Sendable, Codable {
    case plain(DiaryPayload)
    case encrypted(EncryptedDiary)

    public var isEncrypted: Bool {
        if case .encrypted = self { return true }
        return false
    }

    private enum CodingKeys: String, CodingKey { case kind, payload }
    private enum Kind: String, Codable { case plain, encrypted }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .plain: self = .plain(try container.decode(DiaryPayload.self, forKey: .payload))
        case .encrypted: self = .encrypted(try container.decode(EncryptedDiary.self, forKey: .payload))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .plain(let payload):
            try container.encode(Kind.plain, forKey: .kind)
            try container.encode(payload, forKey: .payload)
        case .encrypted(let encrypted):
            try container.encode(Kind.encrypted, forKey: .kind)
            try container.encode(encrypted, forKey: .payload)
        }
    }
}
