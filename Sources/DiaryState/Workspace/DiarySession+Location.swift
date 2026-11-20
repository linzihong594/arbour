import DiaryCore
import Foundation

extension DiarySession {
    /// Attaches a location to the open diary. Only the unlocked session exposes location.
    @discardableResult
    public func setLocation(_ location: DiaryLocation?) -> Bool {
        guard !isBusy, !isLocked else { return false }
        return applyLocation(location)
    }

    /// Requests exactly one fix; denial, timeout and stale fixes keep the diary unchanged.
    @discardableResult
    public func attachCurrentLocation(using provider: any DiaryLocationProviding) async -> Bool {
        guard !isBusy, !isLocked else { return false }
        isBusy = true
        defer { isBusy = false }
        do {
            let newLocation = try await provider.requestCurrentLocation()
            try newLocation.validate()
            return applyLocation(newLocation)
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func applyLocation(_ newLocation: DiaryLocation?) -> Bool {
        guard !isLocked, let markdown = text else { return false }
        do {
            var draft = document
            // A new coordinate invalidates any weather gathered for the previous one.
            let payload = DiaryPayload(markdown: markdown, location: newLocation, weather: nil)
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
            weather = nil
            weatherStatus = nil
            autosave.update(draft)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
