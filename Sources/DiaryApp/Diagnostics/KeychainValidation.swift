import CryptoKit
import DiaryPlatform
import Foundation
import LocalAuthentication
import Security

/// One synthetic key, no authentication UI. Does not read any existing diary or Keychain item.
enum KeychainValidation {
    static func run(output: URL) async throws {
        let data = try await Task.detached {
            let status = BiometricSigningStatus.current()
            let store = BiometricKeyStore(service: "local.mac-diary.synthetic-keychain-validation")
            let id = UUID()
            let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
            var report: [String: Any] = [
                "signing_configured": status.isConfigured,
                "application_identifier": status.applicationIdentifier ?? "missing",
                "team_identifier": status.teamIdentifier ?? "missing",
                "embedded_profile": status.hasEmbeddedProfile,
                "real_fingerprint_tested": false,
            ]
            do {
                report["missing_key_found_before_store"] = try store.contains(id: id)
                try store.save(key, id: id, allowInteraction: false)
                report["protected_write_status"] = 0
                report["protected_key_found_after_store"] = try store.contains(id: id)
                let context = LAContext()
                context.interactionNotAllowed = true
                do {
                    _ = try store.read(id: id, reason: "合成密钥非交互校验", context: context)
                    report["noninteractive_read_blocked"] = false
                } catch {
                    report["noninteractive_read_blocked"] = true
                    report["noninteractive_read_error"] = error.localizedDescription
                }
                do {
                    try store.remove(id: id)
                    report["synthetic_key_removed"] = true
                    report["missing_key_found_after_remove"] = try store.contains(id: id)
                } catch {
                    report["synthetic_key_removed"] = false
                    report["cleanup_error"] = error.localizedDescription
                }
            } catch {
                if case PlatformError.keychain(let code) = error {
                    report["protected_write_status"] = Int(code)
                }
                report["protected_write_error"] = error.localizedDescription
            }
            return try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        }.value
        try data.write(to: output, options: .atomic)
    }
}
