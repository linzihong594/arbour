import DiaryCore
import Foundation
import Testing

struct DiaryWeatherTests {
    private let location = DiaryLocation(
        latitude: 31.2304, longitude: 121.4737, horizontalAccuracy: 12,
        capturedAt: Date(timeIntervalSince1970: 1_700_000_000), source: .current, label: "上海")
    private let weather = DiaryWeather(
        temperatureCelsius: 23.4, apparentTemperatureCelsius: 22.8, weatherCode: 3,
        windSpeedKmh: 8.2, fetchedAt: Date(timeIntervalSince1970: 1_700_000_100),
        source: "Open-Meteo", timeZoneID: "Asia/Shanghai")

    @Test func summaryMatchesWMOCodeGroup() {
        #expect(weather.summaryText == "23° 阴")
        #expect(weather.symbolName == "cloud")
        let rain = DiaryWeather(temperatureCelsius: 18, weatherCode: 63, source: "Open-Meteo")
        #expect(rain.conditionText == "雨")
        #expect(rain.symbolName == "cloud.rain")
        let unknown = DiaryWeather(temperatureCelsius: 18, weatherCode: 42, source: "Open-Meteo")
        #expect(unknown.conditionText == "天气")
    }

    @Test func rejectsOutOfRangeAndWeatherWithoutLocation() throws {
        var invalid = weather
        invalid.temperatureCelsius = 200
        #expect(throws: DiaryStoreError.self) { try invalid.validate() }
        invalid = weather
        invalid.weatherCode = 100
        #expect(throws: DiaryStoreError.self) { try invalid.validate() }
        invalid = weather
        invalid.source = ""
        #expect(throws: DiaryStoreError.self) { try invalid.validate() }

        let orphan = DiaryPayload(markdown: "有天气没有位置", weather: weather)
        #expect(throws: DiaryStoreError.self) { try orphan.validate() }
        #expect(orphan.requiredSchemaVersion == 3)
    }

    @Test func payloadUpgradesVersionForWeather() throws {
        #expect(DiaryPayload(markdown: "无位置").requiredSchemaVersion == 1)
        #expect(DiaryPayload(markdown: "有位置", location: location).requiredSchemaVersion == 2)
        let payload = DiaryPayload(markdown: "有天气", location: location, weather: weather)
        #expect(payload.requiredSchemaVersion == 3)

        var document = DiaryDocument(
            metadata: DiaryMetadata(title: "合成天气日记"), content: .plain(payload))
        document.schemaVersion = 2
        #expect(throws: DiaryStoreError.self) { try document.validate() }
        document.schemaVersion = 3
        try document.validate()
    }

    @Test func currentDayUsesDiaryTimeZone() throws {
        let zone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let day = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 12)))
        let metadata = DiaryMetadata(title: "合成日记", date: day, timeZone: zone)
        let sameDay = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 23)))
        let nextDay = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 0)))

        #expect(DiaryWeatherEligibility.isCurrentDay(metadata: metadata, now: sameDay))
        #expect(!DiaryWeatherEligibility.isCurrentDay(metadata: metadata, now: nextDay))
    }

    @Test func encryptedWeatherStaysInsideCiphertext() throws {
        let payload = DiaryPayload(markdown: "私密天气正文", location: location, weather: weather)
        let metadata = DiaryMetadata(title: "私密天气")
        let result = try DiaryCryptor.encrypt(
            payload, password: "synthetic-weather-password", diaryID: metadata.id)
        var document = DiaryDocument(metadata: metadata, content: .encrypted(result.document))
        document.schemaVersion = 3
        try document.validate()

        let encoded = try DiaryFileCodec.encode(document)
        #expect(encoded.range(of: Data("Open-Meteo".utf8)) == nil)
        #expect(encoded.range(of: Data("上海".utf8)) == nil)
        let unlocked = try DiaryCryptor.unlock(
            result.document, password: "synthetic-weather-password")
        #expect(unlocked.payload.weather == weather)
        #expect(unlocked.payload.location == location)
    }
}
