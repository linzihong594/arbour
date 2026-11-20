import DiaryCore
import Foundation
import LocalAuthentication

/// The lock protects the active request; LAContext.invalidate cancels its system authentication.
public final class SystemBiometricAccess: DiaryBiometricAccess, @unchecked Sendable {
    public let unavailabilityReason: String?
    private let keyStore = BiometricKeyStore()
    private let lock = NSLock()
    private var active: Request?

    public init() {
        let availability = keyStore.availability()
        unavailabilityReason =
            !BiometricSigningStatus.current().isConfigured
            ? "当前构建尚未配置 Touch ID，请继续使用日记密码。"
            : availability.isAvailable ? nil : availability.description
    }

    public func contains(id: UUID) async throws -> Bool {
        guard unavailabilityReason == nil else { return false }
        return try await Task.detached { [keyStore] in try keyStore.contains(id: id) }.value
    }

    public func store(_ key: Data, id: UUID) async throws {
        try requireAvailable()
        try await Task.detached { [keyStore] in try keyStore.save(key, id: id) }.value
    }

    @MainActor public func load(id: UUID) async throws -> Data {
        try requireAvailable()
        let request = Request()
        lock.withLock { active = request }
        defer {
            request.context.invalidate()
            lock.withLock { if active === request { active = nil } }
        }
        return try await Task.detached { [keyStore] in
            try keyStore.read(id: id, reason: "使用 Touch ID 打开这篇私密日记", context: request.context)
        }.value
    }

    public func remove(id: UUID) async throws {
        try requireAvailable()
        try await Task.detached { [keyStore] in try keyStore.remove(id: id) }.value
    }

    public func cancel() {
        let request = lock.withLock {
            let old = active
            active = nil
            return old
        }
        request?.context.invalidate()
    }

    private func requireAvailable() throws {
        if let unavailabilityReason { throw PlatformError.message(unavailabilityReason) }
    }

    private final class Request: @unchecked Sendable {
        let context = LAContext()
    }
}
