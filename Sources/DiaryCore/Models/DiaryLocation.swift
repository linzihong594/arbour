import Foundation

/// Container schema versions. Location is additive from v2 on; weather follows it in v3.
public enum DiarySchema {
    public static let earliestVersion = 1
    public static let currentVersion = 3
}

public enum DiaryLocationSource: String, Codable, Sendable, CaseIterable {
    /// A single fix requested from Core Location on explicit user action.
    case current
    /// A point chosen manually on the map.
    case manual
}

/// A coordinate captured with a timestamp and accuracy. The display label is stored separately.
public struct DiaryLocation: Codable, Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double
    /// Horizontal accuracy in meters; negative values are invalid.
    public var horizontalAccuracy: Double
    public var capturedAt: Date
    public var source: DiaryLocationSource
    /// Optional place name from the map provider; never used to replace the coordinate.
    public var label: String?

    public init(
        latitude: Double,
        longitude: Double,
        horizontalAccuracy: Double,
        capturedAt: Date = .now,
        source: DiaryLocationSource,
        label: String? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.capturedAt = capturedAt
        self.source = source
        self.label = label
    }

    public func validate() throws {
        guard latitude.isFinite, longitude.isFinite, horizontalAccuracy.isFinite,
            (-90...90).contains(latitude), (-180...180).contains(longitude),
            horizontalAccuracy >= 0,
            label.map({ $0.utf8.count <= 512 }) ?? true
        else { throw DiaryStoreError.invalidDocument }
    }

    /// Coordinate fallback when no place name is available; never used in encrypted metadata.
    public var displayText: String {
        if let label, !label.isEmpty { return label }
        return String(format: "%.4f, %.4f", latitude, longitude)
    }
}
