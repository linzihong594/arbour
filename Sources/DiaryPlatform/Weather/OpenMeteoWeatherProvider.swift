import DiaryCore
import Foundation

/// One HTTPS request to Open-Meteo's current-weather endpoint.
///
/// Open-Meteo needs no key, so the app has no account, secret or telemetry. The provider only
/// returns a snapshot; persistence and cancellation of stale requests belong to the session.
@MainActor
public final class OpenMeteoWeatherProvider: DiaryWeatherProviding {
    private static let endpoint = "https://api.open-meteo.com/v1/forecast"
    private static let timeout: TimeInterval = 12

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func currentWeather(for location: DiaryLocation) async throws -> DiaryWeather {
        guard
            var components = URLComponents(string: Self.endpoint)
        else { throw DiaryWeatherRequestError.invalidResponse }
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(location.latitude)),
            URLQueryItem(name: "longitude", value: String(location.longitude)),
            URLQueryItem(
                name: "current",
                value: "temperature_2m,apparent_temperature,weather_code,wind_speed_10m"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        guard let url = components.url else { throw DiaryWeatherRequestError.invalidResponse }
        var request = URLRequest(url: url)
        request.timeoutInterval = Self.timeout

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw Self.translate(error)
        } catch {
            throw DiaryWeatherRequestError.unavailable
        }

        guard let http = response as? HTTPURLResponse else {
            throw DiaryWeatherRequestError.invalidResponse
        }
        if http.statusCode == 429 { throw DiaryWeatherRequestError.rateLimited }
        guard (200..<300).contains(http.statusCode) else {
            throw DiaryWeatherRequestError.server(http.statusCode)
        }

        let decoded: Response
        do {
            decoded = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw DiaryWeatherRequestError.invalidResponse
        }
        guard let temperature = decoded.current.temperature,
            let code = decoded.current.weatherCode
        else { throw DiaryWeatherRequestError.invalidResponse }
        let weather = DiaryWeather(
            temperatureCelsius: temperature,
            apparentTemperatureCelsius: decoded.current.apparentTemperature,
            weatherCode: code,
            windSpeedKmh: decoded.current.windSpeed,
            source: "Open-Meteo",
            timeZoneID: decoded.timezone)
        do {
            try weather.validate()
        } catch {
            throw DiaryWeatherRequestError.invalidResponse
        }
        return weather
    }

    private static func translate(_ error: URLError) -> DiaryWeatherRequestError {
        switch error.code {
        case .timedOut: .timedOut
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
            .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed:
            .offline
        default: .unavailable
        }
    }
}

private struct Response: Decodable {
    let timezone: String?
    let current: Current

    enum CodingKeys: String, CodingKey {
        case timezone
        case current
    }

    struct Current: Decodable {
        let temperature: Double?
        let apparentTemperature: Double?
        let weatherCode: Int?
        let windSpeed: Double?

        enum CodingKeys: String, CodingKey {
            case temperature = "temperature_2m"
            case apparentTemperature = "apparent_temperature"
            case weatherCode = "weather_code"
            case windSpeed = "wind_speed_10m"
        }
    }
}
