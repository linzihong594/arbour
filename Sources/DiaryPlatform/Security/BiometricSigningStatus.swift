import Foundation
import Security

public struct BiometricSigningStatus: Sendable {
    public let applicationIdentifier: String?
    public let teamIdentifier: String?
    public let hasEmbeddedProfile: Bool

    public var isConfigured: Bool {
        applicationIdentifier?.isEmpty == false && teamIdentifier?.isEmpty == false && hasEmbeddedProfile
    }

    public static func current() -> Self {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var information: CFDictionary?
        var entitlements: [String: Any] = [:]
        if SecCodeCopySelf([], &code) == errSecSuccess, let code,
            SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
            SecCodeCopySigningInformation(
                staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
                == errSecSuccess,
            let values = information as? [String: Any]
        {
            entitlements = values[kSecCodeInfoEntitlementsDict as String] as? [String: Any] ?? [:]
        }
        return Self(
            applicationIdentifier: entitlements["com.apple.application-identifier"] as? String,
            teamIdentifier: entitlements["com.apple.developer.team-identifier"] as? String,
            hasEmbeddedProfile: FileManager.default.fileExists(
                atPath: Bundle.main.bundleURL.appendingPathComponent("Contents/embedded.provisionprofile")
                    .path))
    }
}
