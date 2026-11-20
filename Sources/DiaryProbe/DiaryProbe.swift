import CryptoKit
import DiaryCore
import DiaryPlatform
import Foundation

/// Development-only fixtures. Never pass real passwords as command-line arguments.
@main
enum DiaryProbe {
    private static let password = "M1-synthetic-password-2026"
    private static let payload = DiaryPayload(markdown: "## 合成私密日记\n这段正文只用于跨进程恢复验证。")

    static func main() async {
        do {
            try await run()
        } catch {
            FileHandle.standardError.write(Data("FAIL: \(error.localizedDescription)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func run() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        switch arguments.first {
        case "library-write":
            try await LibraryProbe.write(to: path(arguments, index: 1))
        case "backup-fixture":
            try await LibraryProbe.backupFixture(to: path(arguments, index: 1))
        case "backup-create":
            let created = try BackupService.createSnapshot(
                libraryURL: path(arguments, index: 1), backupRoot: path(arguments, index: 2),
                appVersion: "probe")
            print("PASS: \(created.url.path)")
        case "backup-verify":
            let manifest = try BackupService.verifySnapshot(at: path(arguments, index: 1))
            print(
                "PASS: verified \(manifest.entries.count) entries (\(manifest.activeCount) active, \(manifest.trashedCount) trashed, \(manifest.totalBytes) bytes)."
            )
        case "backup-restore":
            let restored = try BackupService.restoreSnapshot(
                at: path(arguments, index: 1), into: path(arguments, index: 2))
            print(
                "PASS: restored \(restored.activeCount) active and \(restored.trashedCount) trashed entries."
            )
        case "library-read":
            try await LibraryProbe.read(from: path(arguments, index: 1))
        case "library-trash":
            try await LibraryProbe.move(directory: path(arguments, index: 1), restoring: false)
        case "library-restore":
            try await LibraryProbe.move(directory: path(arguments, index: 1), restoring: true)
        case "verify-ui-exports":
            try await LibraryProbe.verifyExports(directory: path(arguments, index: 1))
        case "privacy-read":
            try await LibraryProbe.verifyPrivacyReopen(directory: path(arguments, index: 1))
        case "seed-library":
            let count = arguments.count > 2 ? Int(arguments[2]) ?? 0 : 1000
            try await LibraryProbe.seed(directory: path(arguments, index: 1), count: count)
        case "crypto-write":
            let url = try path(arguments, index: 1)
            let encrypted = try DiaryCryptor.encrypt(payload, password: password)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(encrypted.document).write(to: url, options: .atomic)
            print("PASS: wrote synthetic encrypted fixture; no device key required for recovery.")
        case "crypto-read":
            let document = try JSONDecoder().decode(
                EncryptedDiary.self, from: Data(contentsOf: path(arguments, index: 1)))
            guard try DiaryCryptor.unlock(document, password: password).payload == payload else {
                throw PlatformError.message("跨进程恢复的正文不一致。")
            }
            print(
                "PASS: recovered exact synthetic payload in a separate process using only file and password.")
        case "capabilities":
            let status = BiometricKeyStore().availability()
            print("Touch ID available: \(status.isAvailable). \(status.description)")
            print("No authentication dialog or Keychain write was requested.")
        case "keychain-configuration":
            let store = BiometricKeyStore()
            let id = UUID()
            let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
            do {
                try store.save(key, id: id, allowInteraction: false)
                try store.remove(id: id)
                print(
                    "Protected test key can be stored and deleted. Biometric read still requires a manual test."
                )
            } catch {
                print("Protected Keychain configuration unavailable: \(error.localizedDescription)")
            }
        case "bookmark-write":
            let directory = try BackupDirectory(url: path(arguments, index: 1))
            _ = try directory.verifyAccess()
            try directory.bookmark.write(to: path(arguments, index: 2), options: .atomic)
            print("PASS: synthetic directory read/write and bookmark creation.")
        case "bookmark-read":
            let directory = BackupDirectory(bookmark: try Data(contentsOf: path(arguments, index: 1)))
            _ = try directory.verifyAccess()
            print(
                "PASS: directory bookmark resolved and read/write verified in a separate process; upload not verified."
            )
        case "cloud-state":
            let root = try path(arguments, index: 1)
            let target =
                FileManager.default.fileExists(atPath: BackupService.snapshotsRoot(for: root).path)
                ? BackupService.snapshotsRoot(for: root) : root
            let state = BackupCloudInspector.state(of: target)
            print("cloudState=\(state.rawValue) label=\(state.label)")
        default:
            print(
                "Usage: diary-probe crypto-write FILE | crypto-read FILE | capabilities | keychain-configuration | bookmark-write DIRECTORY FILE | bookmark-read FILE | backup-fixture LIBRARY | backup-create LIBRARY BACKUP_ROOT | backup-verify SNAPSHOT | backup-restore SNAPSHOT TARGET | cloud-state BACKUP_ROOT"
            )
        }
    }

    private static func path(_ arguments: [String], index: Int) throws -> URL {
        guard arguments.indices.contains(index) else {
            throw PlatformError.message("缺少测试文件路径。")
        }
        return URL(fileURLWithPath: arguments[index])
    }
}
