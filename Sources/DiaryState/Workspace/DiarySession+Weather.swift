import DiaryCore
import Foundation

extension DiarySession {
    /// Weather belongs to a same-day diary with a confirmed location; past days never ask for today's weather.
    public var canRefreshWeather: Bool {
        guard !isLocked, location != nil else { return false }
        return DiaryWeatherEligibility.isCurrentDay(metadata: document.metadata)
    }

    /// Applies an optional reverse-geocoded name without replacing the coordinate.
    ///
    /// The location snapshot guards against a stale response arriving after the user moved the point.
    @discardableResult
    public func applyPlaceName(_ name: String?, for snapshot: DiaryLocation) -> Bool {
        guard !isLocked, let markdown = text, var current = location, current == snapshot else {
            return false
        }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = trimmed.flatMap { $0.isEmpty ? nil : $0 }
        guard current.label != label else { return false }
        current.label = label
        return commit(
            payload: DiaryPayload(markdown: markdown, location: current, weather: weather),
            location: current)
    }

    /// Requests one weather snapshot. Failures only set a status message and never block editing.
    @discardableResult
    public func refreshWeather(using provider: any DiaryWeatherProviding) async -> Bool {
        guard canRefreshWeather, !isWeatherLoading, let snapshot = location else { return false }
        isWeatherLoading = true
        weatherStatus = nil
        defer { isWeatherLoading = false }
        do {
            let fetched = try await provider.currentWeather(for: snapshot)
            try fetched.validate()
            guard !isLocked, location == snapshot else { return false }
            return applyWeather(fetched, for: snapshot)
        } catch is CancellationError {
            return false
        } catch {
            guard !isLocked, location == snapshot else { return false }
            weatherStatus = error.localizedDescription
            return false
        }
    }

    private func applyWeather(_ newWeather: DiaryWeather, for snapshot: DiaryLocation) -> Bool {
        guard !isLocked, let markdown = text, let current = location, current == snapshot else {
            return false
        }
        let committed = commit(
            payload: DiaryPayload(markdown: markdown, location: current, weather: newWeather),
            location: current)
        if committed {
            weather = newWeather
            weatherStatus = nil
        }
        return committed
    }

    private func commit(payload: DiaryPayload, location newLocation: DiaryLocation) -> Bool {
        do {
            var draft = document
            switch draft.content {
            case .plain:
                draft.content = .plain(payload)
            case .encrypted(let encrypted):
                guard let dataKey else { throw DiaryCryptoError.invalidParameters }
                draft.content = .encrypted(
                    try DiaryCryptor.update(payload, document: encrypted, dataKey: dataKey))
            }
            draft.schemaVersion = max(draft.schemaVersion, payload.requiredSchemaVersion)
            location = newLocation
            autosave.update(draft)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
