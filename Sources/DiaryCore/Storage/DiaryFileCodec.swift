import Foundation

public enum DiaryFileCodec {
    public static let maximumFileBytes = 16 * 1024 * 1024

    public static func encode(_ document: DiaryDocument) throws -> Data {
        try document.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(document)
        guard data.count <= maximumFileBytes else { throw DiaryStoreError.tooLarge }
        return data
    }

    public static func decode(_ data: Data) throws -> DiaryDocument {
        guard data.count <= maximumFileBytes else { throw DiaryStoreError.tooLarge }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        // Read the version first so a future format is preserved, rather than quarantined.
        struct Version: Decodable { let schemaVersion: Int }
        let version = try decoder.decode(Version.self, from: data).schemaVersion
        guard (DiarySchema.earliestVersion...DiarySchema.currentVersion).contains(version) else {
            throw DiaryStoreError.unsupportedVersion(version)
        }
        let document = try decoder.decode(DiaryDocument.self, from: data)
        try document.validate()
        return document
    }
}
