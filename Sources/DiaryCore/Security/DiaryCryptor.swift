import CommonCrypto
import CryptoKit
import Foundation
import Security

public enum DiaryCryptor {
    public static let passwordIterations: UInt32 = 600_000
    private static let keySize = 32
    private static let saltSize = 16

    public static func encrypt(
        _ payload: DiaryPayload,
        password: String,
        diaryID: UUID = UUID()
    ) throws -> EncryptionResult {
        guard password.count >= 8 else { throw DiaryCryptoError.passwordTooShort }

        let parameters = EncryptedDiary.PasswordDerivation(
            algorithm: "PBKDF2-HMAC-SHA256",
            iterations: passwordIterations,
            salt: try randomBytes(count: saltSize)
        )
        let passwordKey = try deriveKey(password: password, parameters: parameters)
        let dataKey = try randomBytes(count: keySize)
        let context = authenticationContext(diaryID: diaryID, parameters: parameters)
        let wrappedKey = try seal(dataKey, key: passwordKey, context: context)
        let encrypted = try seal(
            JSONEncoder().encode(payload),
            key: SymmetricKey(data: dataKey),
            context: context
        )
        return EncryptionResult(
            document: EncryptedDiary(
                version: 1,
                diaryID: diaryID,
                cipher: "AES-256-GCM",
                keyDerivation: parameters,
                wrappedKey: wrappedKey,
                sealedPayload: encrypted
            ),
            dataKey: dataKey
        )
    }

    public static func unlock(_ document: EncryptedDiary, password: String) throws -> UnlockedDiary {
        try validateFormat(document)
        let passwordKey = try deriveKey(password: password, parameters: document.keyDerivation)
        let context = authenticationContext(diaryID: document.diaryID, parameters: document.keyDerivation)
        let dataKey = try open(document.wrappedKey, key: passwordKey, context: context)
        return UnlockedDiary(payload: try decrypt(document, dataKey: dataKey), dataKey: dataKey)
    }

    /// Also used for keys released by a biometric-protected Keychain item.
    public static func decrypt(_ document: EncryptedDiary, dataKey: Data) throws -> DiaryPayload {
        try validateFormat(document)
        guard dataKey.count == keySize else { throw DiaryCryptoError.invalidParameters }
        let context = authenticationContext(diaryID: document.diaryID, parameters: document.keyDerivation)
        let plaintext = try open(document.sealedPayload, key: SymmetricKey(data: dataKey), context: context)
        do {
            return try JSONDecoder().decode(DiaryPayload.self, from: plaintext)
        } catch {
            throw DiaryCryptoError.authenticationFailed
        }
    }

    /// Each edit gets a fresh GCM nonce while keeping the password-wrapped data key.
    public static func update(
        _ payload: DiaryPayload,
        document: EncryptedDiary,
        dataKey: Data
    ) throws -> EncryptedDiary {
        _ = try decrypt(document, dataKey: dataKey)
        let context = authenticationContext(diaryID: document.diaryID, parameters: document.keyDerivation)
        let encrypted = try seal(
            JSONEncoder().encode(payload), key: SymmetricKey(data: dataKey), context: context)
        return EncryptedDiary(
            version: document.version,
            diaryID: document.diaryID,
            cipher: document.cipher,
            keyDerivation: document.keyDerivation,
            wrappedKey: document.wrappedKey,
            sealedPayload: encrypted
        )
    }

    public static func validateFormat(_ document: EncryptedDiary) throws {
        guard document.version == 1, document.cipher == "AES-256-GCM",
            document.keyDerivation.algorithm == "PBKDF2-HMAC-SHA256"
        else {
            throw DiaryCryptoError.unsupportedFormat
        }
        // A fixed v1 cost prevents imported files requesting arbitrarily expensive KDF work.
        guard document.keyDerivation.iterations == passwordIterations,
            document.keyDerivation.salt.count == saltSize,
            document.wrappedKey.count == 60,
            document.sealedPayload.count >= 28
        else {
            throw DiaryCryptoError.invalidParameters
        }
    }

    private static func authenticationContext(
        diaryID: UUID,
        parameters: EncryptedDiary.PasswordDerivation
    ) -> Data {
        let fields = [
            "mac-diary", "1", "AES-256-GCM", diaryID.uuidString,
            parameters.algorithm, String(parameters.iterations), parameters.salt.base64EncodedString(),
        ]
        return Data(fields.joined(separator: "|").utf8)
    }

    private static func deriveKey(
        password: String,
        parameters: EncryptedDiary.PasswordDerivation
    ) throws -> SymmetricKey {
        var bytes = Data(count: keySize)
        let status = bytes.withUnsafeMutableBytes { output in
            parameters.salt.withUnsafeBytes { salt in
                password.withCString { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2), passwordBytes, password.utf8.count,
                        salt.bindMemory(to: UInt8.self).baseAddress, parameters.salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), parameters.iterations,
                        output.bindMemory(to: UInt8.self).baseAddress, keySize
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw DiaryCryptoError.keyDerivationFailed }
        return SymmetricKey(data: bytes)
    }

    private static func randomBytes(count: Int) throws -> Data {
        var bytes = Data(count: count)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else { throw DiaryCryptoError.randomGenerationFailed }
        return bytes
    }

    private static func seal(_ plaintext: Data, key: SymmetricKey, context: Data) throws -> Data {
        guard let combined = try AES.GCM.seal(plaintext, using: key, authenticating: context).combined else {
            throw DiaryCryptoError.invalidParameters
        }
        return combined
    }

    private static func open(_ ciphertext: Data, key: SymmetricKey, context: Data) throws -> Data {
        do {
            let box = try AES.GCM.SealedBox(combined: ciphertext)
            return try AES.GCM.open(box, using: key, authenticating: context)
        } catch {
            throw DiaryCryptoError.authenticationFailed
        }
    }
}
