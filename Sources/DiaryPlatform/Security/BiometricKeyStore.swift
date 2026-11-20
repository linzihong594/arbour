import Foundation
import LocalAuthentication
import Security
import os.log

private let biometricLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "app.arbour.diary", category: "TouchIDKeyStore")

public struct BiometricAvailability: Sendable {
    public let isAvailable: Bool
    public let description: String
}

public struct BiometricKeyStore: Sendable {
    private let service: String

    public init(service: String? = nil) {
        self.service = service ?? "\(Bundle.main.bundleIdentifier ?? "local.mac-diary.probe").diary-keys.v1"
    }

    public func availability() -> BiometricAvailability {
        let context = LAContext()
        defer { context.invalidate() }
        var error: NSError?
        let available =
            context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
            && context.biometryType == .touchID
        return BiometricAvailability(
            isAvailable: available,
            description: available
                ? "此 Mac 可以使用 Touch ID" : (error?.localizedDescription ?? "此 Mac 尚未配置 Touch ID")
        )
    }

    /// This synchronous Keychain call may present system UI; call it away from the main actor.
    public func save(_ key: Data, id: UUID, allowInteraction: Bool = true) throws {
        guard key.count == 32 else { throw PlatformError.message("Touch ID 只能保存有效的日记数据密钥。") }
        var error: Unmanaged<CFError>?
        guard
            let access = SecAccessControlCreateWithFlags(
                nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .biometryCurrentSet, &error
            )
        else {
            if let error { throw error.takeRetainedValue() }
            throw PlatformError.message("无法建立指纹访问控制。")
        }
        var query = itemQuery(id: id)
        let context = LAContext()
        defer { context.invalidate() }
        context.interactionNotAllowed = !allowInteraction
        query[kSecUseAuthenticationContext as String] = context
        query[kSecAttrAccessControl as String] = access
        query[kSecValueData as String] = key
        var status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            // Re-enrollment after password unlock replaces only this local convenience key.
            try remove(id: id)
            status = SecItemAdd(query as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw PlatformError.keychain(status) }
    }

    public func read(id: UUID, reason: String, context: LAContext = LAContext()) throws -> Data {
        context.localizedReason = reason
        context.localizedFallbackTitle = ""
        context.touchIDAuthenticationAllowableReuseDuration = 0
        defer { context.invalidate() }

        var query = itemQuery(id: id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext as String] = context
        biometricLogger.info("TouchID read attempt id=\(id.uuidString, privacy: .public)")
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        biometricLogger.info(
            "TouchID read result id=\(id.uuidString, privacy: .public) status=\(status, privacy: .public)")
        guard status == errSecSuccess, let data = result as? Data else {
            throw PlatformError.keychain(status)
        }
        return data
    }

    /// Noninteractive availability hint; the protected read remains authoritative for key access.
    public func contains(id: UUID) throws -> Bool {
        let context = LAContext()
        context.interactionNotAllowed = true
        defer { context.invalidate() }
        var query = itemQuery(id: id)
        query[kSecUseAuthenticationContext as String] = context
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecItemNotFound { return false }
        // macOS can require authentication even for a protected item's attributes.
        if status == errSecInteractionNotAllowed { return true }
        guard status == errSecSuccess else { throw PlatformError.keychain(status) }
        return true
    }

    public func remove(id: UUID) throws {
        let status = SecItemDelete(itemQuery(id: id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PlatformError.keychain(status)
        }
    }

    private func itemQuery(id: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

}
