import CoreLocation
import DiaryCore
import Foundation
import MapKit

/// Resolves a coordinate to a short place name. The coordinate remains the source of truth;
/// failures are surfaced to the caller so the session can keep showing coordinates.
@MainActor
public final class SystemPlaceNameProvider: DiaryPlaceNameProviding {
    private static let maximumLabelLength = 120

    public init() {}

    public func placeName(for location: DiaryLocation) async throws -> String? {
        let coordinate = CLLocation(latitude: location.latitude, longitude: location.longitude)
        if #available(macOS 26.0, *) {
            guard let request = MKReverseGeocodingRequest(location: coordinate) else { return nil }
            request.preferredLocale = Locale(identifier: "zh_CN")
            let items = try await request.mapItems
            return items.first.flatMap(Self.label(from:))
        } else {
            let placemarks = try await CLGeocoder().reverseGeocodeLocation(coordinate)
            return placemarks.first.flatMap(Self.label(from:))
        }
    }

    private static func label(from item: MKMapItem) -> String? { label(from: item.placemark) }

    private static func label(from placemark: CLPlacemark) -> String? {
        let candidates = [placemark.locality, placemark.subLocality, placemark.administrativeArea]
        guard
            let name = candidates.compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) })
                .first(where: { !$0.isEmpty }) ?? placemark.name
        else { return nil }
        return String(name.prefix(maximumLabelLength))
    }
}
