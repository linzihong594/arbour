import DiaryPlatform
import Foundation
import Testing

struct BackupCloudInspectorTests {
    @Test func ordinaryDirectoryIsReportedAsLocalOnly() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mac-diary-cloud-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("synthetic".utf8).write(
            to: directory.appendingPathComponent("manifest.json"), options: .atomic)

        #expect(BackupCloudInspector.state(of: directory) == .localOnly)
    }

    @Test func missingDirectoryIsUnknown() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mac-diary-missing-\(UUID().uuidString)", isDirectory: true)
        #expect(BackupCloudInspector.state(of: directory) == .unknown)
    }
}
