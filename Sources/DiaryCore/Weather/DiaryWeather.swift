import Foundation

/// A weather snapshot tied to one diary and one confirmed location.
///
/// The snapshot is additive payload data from schema v3. It records the provider and the moment
/// the request finished so a past day can never present today's conditions as its own weather.
public struct DiaryWeather: Codable, Equatable, Sendable {
    public var temperatureCelsius: Double
    public var apparentTemperatureCelsius: Double?
    /// WMO weather interpretation code, as returned by Open-Meteo.
    public var weatherCode: Int
    public var windSpeedKmh: Double?
    /// When the provider finished the request that produced this snapshot.
    public var fetchedAt: Date
    public var source: String
    /// IANA zone used by the weather service for the returned local time.
    public var timeZoneID: String?

    public init(
        temperatureCelsius: Double,
        apparentTemperatureCelsius: Double? = nil,
        weatherCode: Int,
        windSpeedKmh: Double? = nil,
        fetchedAt: Date = .now,
        source: String,
        timeZoneID: String? = nil
    ) {
        self.temperatureCelsius = temperatureCelsius
        self.apparentTemperatureCelsius = apparentTemperatureCelsius
        self.weatherCode = weatherCode
        self.windSpeedKmh = windSpeedKmh
        self.fetchedAt = fetchedAt
        self.source = source
        self.timeZoneID = timeZoneID
    }

    public func validate() throws {
        guard temperatureCelsius.isFinite, (-100...100).contains(temperatureCelsius),
            apparentTemperatureCelsius.map({ $0.isFinite && (-100...100).contains($0) }) ?? true,
            (0...99).contains(weatherCode),
            windSpeedKmh.map({ $0.isFinite && (0...1000).contains($0) }) ?? true,
            !source.isEmpty, source.utf8.count <= 128,
            timeZoneID.map({ $0.utf8.count <= 64 }) ?? true
        else { throw DiaryStoreError.invalidDocument }
    }

    /// WMO condition in Chinese, used for the footer and the accessibility label.
    public var conditionText: String {
        switch weatherCode {
        case 0: "晴"
        case 1: "大部晴朗"
        case 2: "多云"
        case 3: "阴"
        case 45, 48: "雾"
        case 51, 53, 55, 56, 57: "毛毛雨"
        case 61, 63, 65, 66, 67: "雨"
        case 71, 73, 75, 77: "雪"
        case 80, 81, 82: "阵雨"
        case 85, 86: "阵雪"
        case 95, 96, 99: "雷雨"
        default: "天气"
        }
    }

    /// SF Symbol that matches the WMO code; mirrors the same grouping as `conditionText`.
    public var symbolName: String {
        switch weatherCode {
        case 0, 1: "sun.max"
        case 2: "cloud.sun"
        case 3: "cloud"
        case 45, 48: "cloud.fog"
        case 51, 53, 55, 56, 57: "cloud.drizzle"
        case 61, 63, 65, 66, 67, 80, 81, 82: "cloud.rain"
        case 71, 73, 75, 77, 85, 86: "cloud.snow"
        case 95, 96, 99: "cloud.bolt.rain"
        default: "cloud"
        }
    }

    /// Compact footer text such as `23° 多云`; rounds only for display.
    public var summaryText: String {
        "\(Int(temperatureCelsius.rounded()))° \(conditionText)"
    }
}
