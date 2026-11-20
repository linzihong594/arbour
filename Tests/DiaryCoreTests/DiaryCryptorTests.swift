import DiaryCore
import Foundation
import Testing

@Suite(.serialized)
struct DiaryCryptorTests {
    private let password = "only-a-test-password"
    private let payload = DiaryPayload(markdown: "## 私密正文\n中文、emoji 🌿、**Markdown** 和换行。")

    @Test func passwordRoundTripPreservesExactMarkdown() throws {
        let encrypted = try DiaryCryptor.encrypt(payload, password: password)
        let decoded = try JSONDecoder().decode(
            EncryptedDiary.self, from: JSONEncoder().encode(encrypted.document))
        #expect(try DiaryCryptor.unlock(decoded, password: password).payload == payload)
    }

    @Test func wrongPasswordDoesNotReleasePayload() throws {
        let encrypted = try DiaryCryptor.encrypt(payload, password: password)
        #expect(throws: DiaryCryptoError.authenticationFailed) {
            try DiaryCryptor.unlock(encrypted.document, password: "incorrect-password")
        }
    }

    @Test func ciphertextDoesNotContainPlaintext() throws {
        let encrypted = try DiaryCryptor.encrypt(payload, password: password)
        let encoded = try JSONEncoder().encode(encrypted.document)
        #expect(encoded.range(of: Data(payload.markdown.utf8)) == nil)
        #expect(encoded.range(of: Data(password.utf8)) == nil)
        #expect(encoded.range(of: Data(encrypted.dataKey.base64EncodedString().utf8)) == nil)
    }

    @Test func eachDiaryGetsIndependentKeyAndSalt() throws {
        let first = try DiaryCryptor.encrypt(payload, password: password)
        let second = try DiaryCryptor.encrypt(payload, password: password)
        #expect(first.dataKey != second.dataKey)
        #expect(first.document.keyDerivation.salt != second.document.keyDerivation.salt)
        #expect(first.document.sealedPayload != second.document.sealedPayload)
    }

    @Test func tamperedPayloadFailsAuthentication() throws {
        let encrypted = try DiaryCryptor.encrypt(payload, password: password)
        var damaged = encrypted.document.sealedPayload
        damaged[damaged.startIndex + 14] ^= 1
        let document = try mutate(encrypted.document) { $0["sealedPayload"] = damaged.base64EncodedString() }
        #expect(throws: DiaryCryptoError.authenticationFailed) {
            try DiaryCryptor.unlock(document, password: password)
        }
    }

    @Test func changingDiaryIDFailsAuthentication() throws {
        let encrypted = try DiaryCryptor.encrypt(payload, password: password)
        let document = try mutate(encrypted.document) { $0["diaryID"] = UUID().uuidString }
        #expect(throws: DiaryCryptoError.authenticationFailed) {
            try DiaryCryptor.unlock(document, password: password)
        }
    }

    @Test func swappingAnotherDiaryPayloadFailsAuthentication() throws {
        let first = try DiaryCryptor.encrypt(payload, password: password)
        let second = try DiaryCryptor.encrypt(payload, password: password)
        let document = try mutate(first.document) {
            $0["sealedPayload"] = second.document.sealedPayload.base64EncodedString()
        }
        #expect(throws: DiaryCryptoError.authenticationFailed) {
            try DiaryCryptor.unlock(document, password: password)
        }
    }

    @Test func rejectsUnsupportedVersionBeforeKeyDerivation() throws {
        let encrypted = try DiaryCryptor.encrypt(payload, password: password)
        let document = try mutate(encrypted.document) { $0["version"] = 2 }
        #expect(throws: DiaryCryptoError.unsupportedFormat) {
            try DiaryCryptor.unlock(document, password: password)
        }
    }

    @Test func rejectsExcessiveKDFCostBeforeKeyDerivation() throws {
        let encrypted = try DiaryCryptor.encrypt(payload, password: password)
        let document = try mutate(encrypted.document) {
            var parameters = $0["keyDerivation"] as! [String: Any]
            parameters["iterations"] = UInt32.max
            $0["keyDerivation"] = parameters
        }
        #expect(throws: DiaryCryptoError.invalidParameters) {
            try DiaryCryptor.unlock(document, password: password)
        }
    }

    @Test func updateUsesFreshNonceAndKeepsPasswordRecovery() throws {
        let encrypted = try DiaryCryptor.encrypt(payload, password: password)
        let edited = DiaryPayload(markdown: "编辑后的私密正文")
        let updated = try DiaryCryptor.update(
            edited, document: encrypted.document, dataKey: encrypted.dataKey)
        #expect(updated.wrappedKey == encrypted.document.wrappedKey)
        #expect(updated.sealedPayload.prefix(12) != encrypted.document.sealedPayload.prefix(12))
        #expect(try DiaryCryptor.unlock(updated, password: password).payload == edited)
    }

    @Test func unicodePasswordIsSupported() throws {
        let unicodePassword = "记住每一天🌿很重要"
        let encrypted = try DiaryCryptor.encrypt(payload, password: unicodePassword)
        #expect(try DiaryCryptor.unlock(encrypted.document, password: unicodePassword).payload == payload)
    }

    @Test func shortPasswordIsRejected() {
        #expect(throws: DiaryCryptoError.passwordTooShort) {
            try DiaryCryptor.encrypt(payload, password: "short")
        }
    }

    @Test func wrongDataKeyDoesNotDecrypt() throws {
        let encrypted = try DiaryCryptor.encrypt(payload, password: password)
        #expect(throws: DiaryCryptoError.authenticationFailed) {
            try DiaryCryptor.decrypt(encrypted.document, dataKey: Data(repeating: 0, count: 32))
        }
        #expect(throws: DiaryCryptoError.invalidParameters) {
            try DiaryCryptor.decrypt(encrypted.document, dataKey: Data())
        }
    }

    private func mutate(
        _ document: EncryptedDiary,
        change: (inout [String: Any]) -> Void
    ) throws -> EncryptedDiary {
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as! [String: Any]
        change(&object)
        return try JSONDecoder().decode(
            EncryptedDiary.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
