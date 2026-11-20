import DiaryCore
import Foundation

enum LibraryProbe {
    private static let password = "M2-synthetic-password-2026"
    private static let plainID = UUID(uuidString: "10101010-1010-4010-8010-101010101010")!
    private static let privateID = UUID(uuidString: "20202020-2020-4020-8020-202020202020")!
    private static let payload = DiaryPayload(markdown: "## M2 合成正文\n\n| A | B |\n| --- | --- |\n| 一 | 二 |\n")

    static func write(to directory: URL) async throws {
        let store = DiaryRepository(directory: directory)
        guard try await store.index().entries.isEmpty else { throw DiaryStoreError.conflict }
        for id in [plainID, privateID] {
            let metadata = DiaryMetadata(
                id: id, title: id == plainID ? "合成普通日记" : "合成私密日记",
                date: Date(timeIntervalSince1970: 1_700_000_000),
                timeZone: TimeZone(identifier: "Asia/Shanghai")!)
            let content: DiaryContent =
                id == plainID
                ? .plain(payload)
                : .encrypted(
                    try DiaryCryptor.encrypt(payload, password: password, diaryID: id).document)
            _ = try await store.save(
                DiaryDocument(metadata: metadata, content: content), expectedRevision: nil)
        }
        print("PASS: saved ordinary and encrypted synthetic diary containers.")
    }

    /// Fixture for backup validation: two active diaries plus one trashed schema-3 diary that
    /// carries a synthetic location and weather snapshot.
    static func backupFixture(to directory: URL) async throws {
        try await write(to: directory)
        let store = DiaryRepository(directory: directory)
        let id = UUID(uuidString: "30303030-3030-4030-8030-303030303030")!
        let location = DiaryLocation(
            latitude: 31.2304, longitude: 121.4737, horizontalAccuracy: 0,
            capturedAt: Date(timeIntervalSince1970: 1_792_000_000), source: .manual,
            label: "合成地点")
        let weather = DiaryWeather(
            temperatureCelsius: 21.5, apparentTemperatureCelsius: 20.8, weatherCode: 2,
            windSpeedKmh: 6.4, fetchedAt: Date(timeIntervalSince1970: 1_792_000_100),
            source: "Open-Meteo", timeZoneID: "Asia/Shanghai")
        var document = DiaryDocument(
            metadata: DiaryMetadata(
                id: id, title: "合成带位置天气日记",
                date: Date(timeIntervalSince1970: 1_792_000_000),
                timeZone: TimeZone(identifier: "Asia/Shanghai")!),
            content: .plain(
                DiaryPayload(
                    markdown: "## 合成废纸篓正文\n\n这一段只用于备份与恢复验证。\n",
                    location: location, weather: weather)))
        document.schemaVersion = 3
        _ = try await store.save(document, expectedRevision: nil)
        let saved = try await store.index().entries.first { $0.id == id }
        guard let saved else { throw DiaryStoreError.invalidDocument }
        _ = try await store.trash(id: id, expectedRevision: saved.metadata.revision)
        print("PASS: created backup fixture with 2 active diaries and 1 trashed schema-3 diary.")
    }

    static func read(from directory: URL) async throws {
        let store = DiaryRepository(directory: directory)
        let index = try await store.index()
        guard index.entries.count == 2, index.issues.isEmpty else { throw DiaryStoreError.invalidDocument }
        let plain = try await store.load(id: plainID)
        let privateEntry = try await store.load(id: privateID)
        guard case .plain(let decoded) = plain.content, decoded == payload,
            case .encrypted(let encrypted) = privateEntry.content,
            try DiaryCryptor.unlock(encrypted, password: password).payload == payload
        else {
            throw DiaryStoreError.invalidDocument
        }
        print(
            "PASS: rebuilt metadata index and recovered exact ordinary/encrypted diaries in a fresh process.")
    }

    static func seed(directory: URL, count: Int) async throws {
        guard (1...10_000).contains(count) else { throw DiaryStoreError.invalidDocument }
        let store = DiaryRepository(directory: directory)
        let index = try await store.index()
        guard index.entries.isEmpty, index.issues.isEmpty else { throw DiaryStoreError.conflict }
        let paragraph = "## 合成段落\n\n记录一段值得记住的日常，包含 **粗体** 和 *斜体*。\n\n"
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        for number in 0..<count {
            let body =
                number == count - 1
                ? String(String(repeating: paragraph, count: 300).prefix(10_000))
                : "合成日记 \(number)\n\n" + String(repeating: "轻量化验证的合成段落。\n", count: 12)
            let metadata = DiaryMetadata(
                title: "合成日记 \(number)", date: start.addingTimeInterval(Double(number)))
            _ = try await store.save(
                DiaryDocument(metadata: metadata, content: .plain(DiaryPayload(markdown: body))),
                expectedRevision: nil)
        }
        print("PASS: seeded \(count) synthetic diaries; newest entry contains 10,000 characters.")
    }

    static func move(directory: URL, restoring: Bool) async throws {
        let store = DiaryRepository(directory: directory)
        let index = try await store.index()
        let summaries = restoring ? index.trashedEntries : index.entries
        guard summaries.count == 2, Set(summaries.map(\.id)) == Set([plainID, privateID]) else {
            throw DiaryStoreError.invalidDocument
        }
        for summary in summaries {
            if restoring {
                _ = try await store.restore(id: summary.id, expectedRevision: summary.metadata.revision)
            } else {
                _ = try await store.trash(id: summary.id, expectedRevision: summary.metadata.revision)
            }
        }
        print(
            restoring
                ? "PASS: restored ordinary and encrypted containers in a fresh process."
                : "PASS: moved ordinary and encrypted containers to Trash without decoding private bodies.")
    }

    static func verifyExports(directory: URL) async throws {
        let store = DiaryRepository(directory: directory)
        let plain = try await store.load(id: plainID)
        let privateEntry = try await store.load(id: privateID)
        guard case .plain(let payload) = plain.content, case .encrypted(let encrypted) = privateEntry.content
        else { throw DiaryStoreError.invalidDocument }
        let unlocked = try DiaryCryptor.unlock(encrypted, password: password).payload
        for (document, markdown) in [(plain, payload.markdown), (privateEntry, unlocked.markdown)] {
            let exported = directory.deletingLastPathComponent()
                .appendingPathComponent(MarkdownExport.suggestedName(for: document.metadata))
            guard try Data(contentsOf: exported) == Data(markdown.utf8) else {
                throw DiaryStoreError.invalidDocument
            }
        }
        print(
            "PASS: ordinary and private UI exports exactly match persisted Markdown, verified in a fresh process."
        )
    }

    static func verifyPrivacyReopen(directory: URL) async throws {
        let store = DiaryRepository(directory: directory)
        let privateEntry = try await store.load(id: privateID)
        let ordinary = try await store.load(id: plainID)
        guard case .encrypted(let encrypted) = privateEntry.content,
            try DiaryCryptor.unlock(encrypted, password: password).payload.markdown
                .contains("SEC005-NATIVE-合成补记"),
            ordinary.metadata.title == String(repeating: "用于窄窗口回归的合成长标题🌿", count: 20)
        else { throw DiaryStoreError.invalidDocument }
        print("PASS: private pending edit and complete long title recovered in a fresh process.")
    }
}
