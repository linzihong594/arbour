import Foundation

/// Stores only per-diary data keys. Implementations must enforce biometrics when releasing a key.
public protocol DiaryBiometricAccess: Sendable {
    var unavailabilityReason: String? { get }
    func contains(id: UUID) async throws -> Bool
    func store(_ key: Data, id: UUID) async throws
    @MainActor func load(id: UUID) async throws -> Data
    func remove(id: UUID) async throws
    func cancel()
}
