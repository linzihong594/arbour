import DiaryCore
import Foundation

public struct DiaryFilter: Equatable, Sendable {
    public var titleQuery = ""
    public var day: String?

    public init() {}

    public func matches(_ entry: DiarySummary) -> Bool {
        let query = titleQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return (day == nil || entry.metadata.day == day)
            && (query.isEmpty
                || entry.metadata.title.range(of: query, options: [.caseInsensitive, .diacriticInsensitive])
                    != nil)
    }
}
