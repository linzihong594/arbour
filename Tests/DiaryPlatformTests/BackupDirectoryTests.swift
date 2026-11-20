import DiaryPlatform
import Foundation
import Testing

struct BackupDirectoryTests {
    @Test func bookmarkRoundTripAndProbeCleanup() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }

        let original = try BackupDirectory(url: url)
        let restored = BackupDirectory(bookmark: original.bookmark)
        let result = try restored.verifyAccess()
        #expect(result.url.resolvingSymlinksInPath() == url.resolvingSymlinksInPath())
        #expect(try FileManager.default.contentsOfDirectory(atPath: url.path).isEmpty)
    }

    @Test func malformedBookmarkFailsWithoutWritingFiles() {
        let directory = BackupDirectory(bookmark: Data("not a bookmark".utf8))
        #expect(throws: (any Error).self) { try directory.verifyAccess() }
    }

    @Test func missingDirectoryFailsWithoutCreatingIt() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let directory = try BackupDirectory(url: url)
        try FileManager.default.removeItem(at: url)
        #expect(throws: (any Error).self) { try directory.verifyAccess() }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
