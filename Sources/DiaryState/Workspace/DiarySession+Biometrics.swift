import DiaryCore
import Foundation
import os.log

private let sessionLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "app.arbour.diary", category: "TouchIDSession")

extension DiarySession {
    public var biometricUnavailableReason: String? {
        biometrics?.unavailabilityReason ?? (biometrics == nil ? "当前构建不支持 Touch ID。" : nil)
    }

    public func refreshBiometricStatus() async {
        guard document.content.isEncrypted, let biometrics, biometricUnavailableReason == nil else { return }
        let revision = biometricStatusRevision
        do {
            let exists = try await biometrics.contains(id: document.metadata.id)
            if revision == biometricStatusRevision { isBiometricEnabled = exists }
        } catch {
            // A failed metadata lookup does not prevent password unlock.
            if revision == biometricStatusRevision { isBiometricEnabled = false }
        }
    }

    @discardableResult
    public func enableTouchID() async -> Bool {
        guard !isBusy, !isLocked, document.content.isEncrypted, let dataKey, let biometrics else {
            return false
        }
        if let reason = biometricUnavailableReason {
            errorMessage = reason
            return false
        }
        isBusy = true
        biometricStatusRevision += 1
        let revision = unlockRevision
        defer { isBusy = false }
        do {
            try await biometrics.store(dataKey, id: document.metadata.id)
            guard revision == unlockRevision else {
                try? await biometrics.remove(id: document.metadata.id)
                isBiometricEnabled = false
                return false
            }
            isBiometricEnabled = true
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    public func disableTouchID() async -> Bool {
        guard !isBusy, let biometrics else { return false }
        isBusy = true
        biometricStatusRevision += 1
        defer { isBusy = false }
        do {
            try await biometrics.remove(id: document.metadata.id)
            isBiometricEnabled = false
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    public func unlockWithTouchID() async -> Bool {
        guard !isBusy, isLocked, let biometrics, case .encrypted(let encrypted) = document.content else {
            return false
        }
        if let reason = biometricUnavailableReason {
            errorMessage = reason
            return false
        }
        isBusy = true
        errorMessage = nil
        let revision = unlockRevision
        sessionLogger.info("TouchID unlock initiated revision=\(revision, privacy: .public)")
        defer { isBusy = false }
        do {
            let key = try await biometrics.load(id: document.metadata.id)
            guard revision == unlockRevision else {
                sessionLogger.warning(
                    "TouchID unlock rejected: revision mismatch (\(revision, privacy: .public) != \(self.unlockRevision, privacy: .public))"
                )
                return false
            }
            let payload = try await Task.detached(priority: .userInitiated) {
                try DiaryCryptor.decrypt(encrypted, dataKey: key)
            }.value
            guard revision == unlockRevision else {
                sessionLogger.warning(
                    "TouchID unlock rejected after decrypt: revision mismatch (\(revision, privacy: .public) != \(self.unlockRevision, privacy: .public))"
                )
                return false
            }
            text = payload.markdown
            dataKey = key
            isBiometricEnabled = true
            editorIdentity = UUID()
            sessionLogger.info("TouchID unlock succeeded revision=\(revision, privacy: .public)")
            return true
        } catch {
            sessionLogger.info(
                "TouchID unlock failed revision=\(revision, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            if revision == unlockRevision { errorMessage = error.localizedDescription }
            return false
        }
    }
}
