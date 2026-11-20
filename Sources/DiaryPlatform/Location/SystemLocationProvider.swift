import CoreLocation
import DiaryCore
import Foundation

/// One-shot Core Location provider. Every finish path stops updates; callbacks hop to the main actor.
@MainActor
public final class SystemLocationProvider: NSObject, DiaryLocationProviding {
    /// Time allowed for the user to answer the system authorization prompt.
    private static let authorizationTimeout: Duration = .seconds(30)
    /// Time allowed for Core Location to produce a fix after authorization.
    private static let fixTimeout: Duration = .seconds(20)
    private static let maximumFixAge: TimeInterval = 15

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<DiaryLocation, any Error>?
    private var timeoutTask: Task<Void, Never>?

    public override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    public func requestCurrentLocation() async throws -> DiaryLocation {
        guard continuation == nil else { throw DiaryLocationRequestError.unavailable }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            switch manager.authorizationStatus {
            case .notDetermined:
                startTimeout(Self.authorizationTimeout)
                manager.requestWhenInUseAuthorization()
            case .restricted:
                finish(.failure(DiaryLocationRequestError.restricted))
            case .denied:
                finish(.failure(DiaryLocationRequestError.denied))
            case .authorizedAlways, .authorizedWhenInUse:
                startFixRequest()
            @unknown default:
                finish(.failure(DiaryLocationRequestError.unavailable))
            }
        }
    }

    private func startFixRequest() {
        startTimeout(Self.fixTimeout)
        manager.requestLocation()
    }

    private func startTimeout(_ duration: Duration) {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.finish(.failure(DiaryLocationRequestError.timeout))
        }
    }

    private func finish(_ result: Result<DiaryLocation, any Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        manager.stopUpdatingLocation()
        continuation.resume(with: result)
    }

    private func handleAuthorization(_ status: CLAuthorizationStatus) {
        guard continuation != nil else { return }
        switch status {
        case .notDetermined:
            break
        case .restricted:
            finish(.failure(DiaryLocationRequestError.restricted))
        case .denied:
            finish(.failure(DiaryLocationRequestError.denied))
        case .authorizedAlways, .authorizedWhenInUse:
            startFixRequest()
        @unknown default:
            finish(.failure(DiaryLocationRequestError.unavailable))
        }
    }

    private func receive(_ fix: Fix?) {
        guard let fix else { return finish(.failure(DiaryLocationRequestError.unavailable)) }
        guard fix.timestamp.timeIntervalSinceNow > -Self.maximumFixAge else {
            return finish(.failure(DiaryLocationRequestError.stale))
        }
        let location = DiaryLocation(
            latitude: fix.latitude,
            longitude: fix.longitude,
            horizontalAccuracy: fix.horizontalAccuracy,
            capturedAt: fix.timestamp,
            source: .current)
        do {
            try location.validate()
            finish(.success(location))
        } catch {
            finish(.failure(DiaryLocationRequestError.unavailable))
        }
    }

    private func receiveFailure(_ code: Int) {
        if CLError.Code(rawValue: code) == .denied {
            finish(.failure(DiaryLocationRequestError.denied))
        } else {
            finish(.failure(DiaryLocationRequestError.unavailable))
        }
    }
}

extension SystemLocationProvider: CLLocationManagerDelegate {
    public nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in self?.handleAuthorization(status) }
    }

    public nonisolated func locationManager(
        _ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]
    ) {
        let fix = locations.last.map(Fix.init)
        Task { @MainActor [weak self] in self?.receive(fix) }
    }

    public nonisolated func locationManager(
        _ manager: CLLocationManager, didFailWithError error: any Error
    ) {
        let code = (error as NSError).code
        Task { @MainActor [weak self] in self?.receiveFailure(code) }
    }
}

private struct Fix: Sendable {
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
    let timestamp: Date

    init(_ location: CLLocation) {
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        horizontalAccuracy = location.horizontalAccuracy
        timestamp = location.timestamp
    }
}
