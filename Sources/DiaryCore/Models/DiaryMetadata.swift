import Foundation

public struct DiaryMetadata: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public let day: String
    public let timeZoneID: String
    public let createdAt: Date
    public var updatedAt: Date
    public var revision: UInt64

    public init(id: UUID = UUID(), title: String, date: Date = .now, timeZone: TimeZone = .current) {
        self.id = id
        self.title = title
        timeZoneID = timeZone.identifier
        createdAt = Self.timestamp(date)
        updatedAt = createdAt
        revision = 0
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        day = String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    public var diaryDate: Date? {
        guard let zone = TimeZone(identifier: timeZoneID) else { return nil }
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...9999).contains(parts[0]),
            day == String(format: "%04d-%02d-%02d", parts[0], parts[1], parts[2])
        else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)
        guard let date = calendar.date(from: components),
            calendar.dateComponents([.year, .month, .day], from: date).year == parts[0],
            calendar.component(.month, from: date) == parts[1],
            calendar.component(.day, from: date) == parts[2]
        else { return nil }
        return date
    }

    public static func timestamp(_ date: Date) -> Date {
        Date(timeIntervalSince1970: floor(date.timeIntervalSince1970 * 1000) / 1000)
    }
}

public struct DiarySummary: Equatable, Identifiable, Sendable {
    public let metadata: DiaryMetadata
    public let isEncrypted: Bool
    public var id: UUID { metadata.id }

    public init(metadata: DiaryMetadata, isEncrypted: Bool) {
        self.metadata = metadata
        self.isEncrypted = isEncrypted
    }

    public static func newestFirst(_ lhs: Self, _ rhs: Self) -> Bool {
        if lhs.metadata.day != rhs.metadata.day { return lhs.metadata.day > rhs.metadata.day }
        if lhs.metadata.createdAt != rhs.metadata.createdAt {
            return lhs.metadata.createdAt > rhs.metadata.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
