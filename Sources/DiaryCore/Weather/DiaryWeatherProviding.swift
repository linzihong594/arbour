import Foundation

/// Resolves a confirmed coordinate to an optional short place name.
///
/// A missing name is not a failure: the coordinate stays authoritative and remains visible.
@MainActor
public protocol DiaryPlaceNameProviding {
    func placeName(for location: DiaryLocation) async throws -> String?
}

/// Fetches one weather snapshot for a confirmed coordinate.
@MainActor
public protocol DiaryWeatherProviding {
    func currentWeather(for location: DiaryLocation) async throws -> DiaryWeather
}

public enum DiaryWeatherRequestError: LocalizedError, Equatable, Sendable {
    case offline
    case timedOut
    case rateLimited
    case server(Int)
    case invalidResponse
    case unavailable

    public var errorDescription: String? {
        switch self {
        case .offline: "网络不可用，天气未更新。日记仍可继续写。"
        case .timedOut: "天气请求超时，日记仍可继续写。"
        case .rateLimited: "天气服务请求过于频繁，请稍后重试。"
        case .server(let status): "天气服务返回错误（HTTP \(status)），日记仍可继续写。"
        case .invalidResponse: "天气数据无法解析，日记仍可继续写。"
        case .unavailable: "暂时无法获取天气，日记仍可继续写。"
        }
    }
}

/// Weather is only fetched for the diary whose day matches the current day in its own time zone.
public enum DiaryWeatherEligibility {
    public static func isCurrentDay(
        metadata: DiaryMetadata, now: Date = .now, calendar base: Calendar = Calendar(identifier: .gregorian)
    ) -> Bool {
        guard let zone = TimeZone(identifier: metadata.timeZoneID) else { return false }
        var calendar = base
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return false }
        return metadata.day == String(format: "%04d-%02d-%02d", year, month, day)
    }
}
