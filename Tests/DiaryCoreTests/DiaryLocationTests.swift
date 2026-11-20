import DiaryCore
import Foundation
import Testing

struct DiaryLocationTests {
    private let sample = DiaryLocation(
        latitude: 31.2304, longitude: 121.4737, horizontalAccuracy: 12,
        capturedAt: Date(timeIntervalSince1970: 1_700_000_000), source: .current, label: "上海")

    @Test func validatesCoordinateRangesAndAccuracy() throws {
        try sample.validate()
        #expect(throws: DiaryStoreError.invalidDocument) {
            try DiaryLocation(latitude: 91, longitude: 0, horizontalAccuracy: 10, source: .current)
                .validate()
        }
        #expect(throws: DiaryStoreError.invalidDocument) {
            try DiaryLocation(latitude: 0, longitude: -181, horizontalAccuracy: 10, source: .current)
                .validate()
        }
        #expect(throws: DiaryStoreError.invalidDocument) {
            try DiaryLocation(latitude: 0, longitude: 0, horizontalAccuracy: -1, source: .current)
                .validate()
        }
    }

    @Test func plainDocumentWithLocationRoundTripsAsSchemaTwo() throws {
        var document = DiaryDocument(
            metadata: DiaryMetadata(title: "合成位置"),
            content: .plain(DiaryPayload(markdown: "带位置的正文", location: sample)))
        // Extended payloads must be written as v2 so older builds preserve instead of dropping.
        document.schemaVersion = 2
        let decoded = try DiaryFileCodec.decode(DiaryFileCodec.encode(document))
        #expect(decoded.schemaVersion == 2)
        #expect(decoded.content == document.content)
        guard case .plain(let payload) = decoded.content else {
            Issue.record("Expected plain payload")
            return
        }
        #expect(payload.location == sample)
    }

    @Test func documentWithoutLocationStaysSchemaOne() throws {
        let document = DiaryDocument(
            metadata: DiaryMetadata(title: "普通正文"),
            content: .plain(DiaryPayload(markdown: "没有位置")))
        #expect(document.schemaVersion == 1)
        let decoded = try DiaryFileCodec.decode(DiaryFileCodec.encode(document))
        #expect(decoded.schemaVersion == 1)
        guard case .plain(let payload) = decoded.content else {
            Issue.record("Expected plain payload")
            return
        }
        #expect(payload.location == nil)
    }

    @Test func encryptedPayloadKeepsLocationInsideCiphertext() throws {
        let payload = DiaryPayload(markdown: "私密正文", location: sample)
        let encrypted = try DiaryCryptor.encrypt(payload, password: "location-test-password")
        let file = try JSONEncoder().encode(encrypted.document)
        #expect(file.range(of: Data(sample.displayText.utf8)) == nil)
        let unlocked = try DiaryCryptor.unlock(
            encrypted.document, password: "location-test-password")
        #expect(unlocked.payload == payload)
    }

    @Test func manualSelectionKeepsSource() throws {
        let manual = DiaryLocation(
            latitude: 22.5431, longitude: 114.0579, horizontalAccuracy: 0,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000), source: .manual)
        var document = DiaryDocument(
            metadata: DiaryMetadata(title: "地图选点"),
            content: .plain(DiaryPayload(markdown: "手动选点", location: manual)))
        document.schemaVersion = 2
        let decoded = try DiaryFileCodec.decode(DiaryFileCodec.encode(document))
        guard case .plain(let payload) = decoded.content else {
            Issue.record("Expected plain payload")
            return
        }
        #expect(payload.location?.source == .manual)
        #expect(payload.location == manual)
    }

    @Test func schemaOneWithLocationIsRejectedBeforeWrite() {
        var document = DiaryDocument(
            metadata: DiaryMetadata(title: "版本不一致"),
            content: .plain(DiaryPayload(markdown: "", location: sample)))
        document.schemaVersion = 1
        #expect(throws: DiaryStoreError.invalidDocument) { try document.validate() }
    }
}
