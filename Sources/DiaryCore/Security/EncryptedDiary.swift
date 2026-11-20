import Foundation

/// Versioned, portable ciphertext. Titles belong to the public diary index.
public struct EncryptedDiary: Codable, Equatable, Sendable {
    public let version: Int
    public let diaryID: UUID
    public let cipher: String
    public let keyDerivation: PasswordDerivation
    public let wrappedKey: Data
    public let sealedPayload: Data

    public struct PasswordDerivation: Codable, Equatable, Sendable {
        public let algorithm: String
        public let iterations: UInt32
        public let salt: Data
    }
}

public struct DiaryPayload: Codable, Equatable, Sendable {
    public var markdown: String
    /// Additive v2 field; older v1 documents decode with nil.
    public var location: DiaryLocation?
    /// Additive v3 field; requires a confirmed location and a same-day diary.
    public var weather: DiaryWeather?

    public init(markdown: String, location: DiaryLocation? = nil, weather: DiaryWeather? = nil) {
        self.markdown = markdown
        self.location = location
        self.weather = weather
    }

    public var requiredSchemaVersion: Int {
        if weather != nil { return 3 }
        return location == nil ? DiarySchema.earliestVersion : 2
    }

    public func validate() throws {
        try location?.validate()
        try weather?.validate()
        guard weather == nil || location != nil else { throw DiaryStoreError.invalidDocument }
    }
}

public struct UnlockedDiary: Sendable {
    public let payload: DiaryPayload
    public let dataKey: Data
}

public struct EncryptionResult: Sendable {
    public let document: EncryptedDiary
    public let dataKey: Data
}
