import DiaryCore
import DiaryState
import Foundation
import Testing

@MainActor
struct WeatherSessionTests {
    private let location = DiaryLocation(
        latitude: 31.2304, longitude: 121.4737, horizontalAccuracy: 12,
        capturedAt: Date(timeIntervalSince1970: 1_700_000_000), source: .current, label: "上海")
    private let moved = DiaryLocation(
        latitude: 22.8348, longitude: 113.1849, horizontalAccuracy: 0,
        capturedAt: Date(timeIntervalSince1970: 1_700_000_500), source: .manual)
    private let weather = DiaryWeather(
        temperatureCelsius: 23.4, apparentTemperatureCelsius: 22.8, weatherCode: 3,
        windSpeedKmh: 8.2, fetchedAt: Date(timeIntervalSince1970: 1_700_000_100),
        source: "Open-Meteo", timeZoneID: "Asia/Shanghai")

    @Test func refreshesWeatherForCurrentDayAndPersists() async throws {
        let store = MemoryStore()
        let saved = try await store.save(document(), expectedRevision: nil)
        let session = DiarySession(document: saved, store: store)
        #expect(session.setLocation(location))
        #expect(await session.autosave.flush())
        let provider = StubWeatherProvider(result: .success(weather))

        #expect(await session.refreshWeather(using: provider))
        #expect(provider.requestCount == 1)
        #expect(session.weather == weather)
        #expect(session.weather?.source == "Open-Meteo")
        #expect(!session.isBusy)

        #expect(await session.autosave.flush())
        let stored = try await store.load(id: saved.metadata.id)
        #expect(stored.schemaVersion == 3)
        guard case .plain(let payload) = stored.content else {
            Issue.record("Expected plain payload")
            return
        }
        #expect(payload.location == location)
        #expect(payload.weather == weather)
    }

    @Test func failedRequestKeepsDiaryWritableAndCoordinates() async throws {
        let store = MemoryStore()
        let saved = try await store.save(document(), expectedRevision: nil)
        let session = DiarySession(document: saved, store: store)
        #expect(session.setLocation(location))
        #expect(await session.autosave.flush())
        let before = try await store.load(id: saved.metadata.id)
        let provider = StubWeatherProvider(result: .failure(.offline))

        #expect(await session.refreshWeather(using: provider) == false)
        #expect(session.weather == nil)
        #expect(session.location == location)
        #expect(session.weatherStatus == DiaryWeatherRequestError.offline.localizedDescription)
        #expect(session.errorMessage == nil)
        #expect(!session.isBusy)

        session.editMarkdown("天气失败后仍可继续写")
        #expect(await session.autosave.flush())
        let stored = try await store.load(id: saved.metadata.id)
        #expect(stored.metadata.revision > before.metadata.revision)
        guard case .plain(let payload) = stored.content else {
            Issue.record("Expected plain payload")
            return
        }
        #expect(payload.markdown == "天气失败后仍可继续写")
        #expect(payload.weather == nil)
        #expect(payload.location == location)
    }

    @Test func pastDayNeverRequestsTodaysWeather() async throws {
        let store = MemoryStore()
        let metadata = DiaryMetadata(
            title: "过去日记", date: Date(timeIntervalSinceNow: -86_400), timeZone: .current)
        let saved = try await store.save(
            DiaryDocument(
                metadata: metadata,
                content: .plain(DiaryPayload(markdown: "过去日期的正文"))),
            expectedRevision: nil)
        let session = DiarySession(document: saved, store: store)
        #expect(session.setLocation(location))
        #expect(!session.canRefreshWeather)
        let provider = StubWeatherProvider(result: .success(weather))

        #expect(await session.refreshWeather(using: provider) == false)
        #expect(provider.requestCount == 0)
        #expect(session.weather == nil)
        #expect(session.weatherStatus == nil)
    }

    @Test func movingThePointDropsAStaleWeatherResult() async throws {
        let store = MemoryStore()
        let saved = try await store.save(document(), expectedRevision: nil)
        let session = DiarySession(document: saved, store: store)
        #expect(session.setLocation(location))
        let provider = SuspendedWeatherProvider()
        let request = Task { await session.refreshWeather(using: provider) }
        while !provider.started { await Task.yield() }
        #expect(session.isWeatherLoading)

        #expect(session.setLocation(moved))
        #expect(session.weather == nil)
        provider.finish(.success(weather))
        #expect(await request.value == false)
        #expect(session.weather == nil)
        #expect(session.location == moved)

        #expect(await session.autosave.flush())
        let stored = try await store.load(id: saved.metadata.id)
        #expect(stored.schemaVersion == 2)
        guard case .plain(let payload) = stored.content else {
            Issue.record("Expected plain payload")
            return
        }
        #expect(payload.weather == nil)
        #expect(payload.location == moved)
    }

    @Test func placeNameOnlyChangesTheLabel() async throws {
        let store = MemoryStore()
        let saved = try await store.save(document(), expectedRevision: nil)
        let session = DiarySession(document: saved, store: store)
        #expect(session.setLocation(location))
        #expect(await session.refreshWeather(using: StubWeatherProvider(result: .success(weather))))
        let snapshot = try #require(session.location)

        #expect(session.applyPlaceName("上海市", for: snapshot))
        #expect(session.location?.label == "上海市")
        #expect(session.location?.latitude == location.latitude)
        #expect(session.weather == weather)
        #expect(await session.autosave.flush())
        guard case .plain(let payload) = try await store.load(id: saved.metadata.id).content else {
            Issue.record("Expected plain payload")
            return
        }
        #expect(payload.location?.label == "上海市")
        #expect(payload.weather == weather)

        #expect(session.applyPlaceName(nil, for: try #require(session.location)))
        #expect(session.location?.label == nil)
        #expect(session.location?.displayText == "31.2304, 121.4737")
    }

    @Test func stalePlaceNameDoesNotOverwriteANewPoint() async throws {
        let store = MemoryStore()
        let saved = try await store.save(document(), expectedRevision: nil)
        let session = DiarySession(document: saved, store: store)
        #expect(session.setLocation(location))
        let old = try #require(session.location)
        #expect(session.setLocation(moved))

        #expect(session.applyPlaceName("旧地点", for: old) == false)
        #expect(session.location == moved)
        #expect(session.location?.label == nil)
    }

    @Test func lockedDiaryNeitherShowsNorFetchesWeather() async throws {
        let store = MemoryStore()
        let saved = try await store.save(document(), expectedRevision: nil)
        let session = DiarySession(document: saved, store: store)
        #expect(session.setLocation(location))
        #expect(await session.encrypt(password: "synthetic-weather-password"))
        #expect(session.isLocked)
        let provider = StubWeatherProvider(result: .success(weather))

        #expect(session.canRefreshWeather == false)
        #expect(await session.refreshWeather(using: provider) == false)
        #expect(provider.requestCount == 0)
        #expect(session.weather == nil)
        #expect(session.location == nil)
        #expect(session.applyPlaceName("泄露", for: self.location) == false)
    }

    private func document() -> DiaryDocument {
        DiaryDocument(
            metadata: DiaryMetadata(title: "合成天气日记"),
            content: .plain(DiaryPayload(markdown: "带位置的正文")))
    }
}

@MainActor
private final class StubWeatherProvider: DiaryWeatherProviding {
    let result: Result<DiaryWeather, DiaryWeatherRequestError>
    private(set) var requestCount = 0

    init(result: Result<DiaryWeather, DiaryWeatherRequestError>) {
        self.result = result
    }

    func currentWeather(for location: DiaryLocation) async throws -> DiaryWeather {
        requestCount += 1
        switch result {
        case .success(let weather): return weather
        case .failure(let error): throw error
        }
    }
}

@MainActor
private final class SuspendedWeatherProvider: DiaryWeatherProviding {
    private(set) var started = false
    private var continuation: CheckedContinuation<DiaryWeather, any Error>?

    func currentWeather(for location: DiaryLocation) async throws -> DiaryWeather {
        started = true
        return try await withCheckedThrowingContinuation { self.continuation = $0 }
    }

    func finish(_ result: Result<DiaryWeather, DiaryWeatherRequestError>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}
