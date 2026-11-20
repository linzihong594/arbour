import DiaryCore
import Foundation
import Observation

/// A single open editor session; persisted drafts contain ciphertext when the diary is private.
@MainActor @Observable
public final class DiarySession {
    public let autosave: DiaryAutosave
    public internal(set) var text: String?
    public internal(set) var location: DiaryLocation?
    public internal(set) var weather: DiaryWeather?
    public internal(set) var weatherStatus: String?
    public internal(set) var isWeatherLoading = false
    public internal(set) var editorIdentity = UUID()
    public internal(set) var isBusy = false
    public internal(set) var isBiometricEnabled = false
    public var errorMessage: String?
    var dataKey: Data?
    var unlockRevision = 0
    var biometricStatusRevision = 0
    let biometrics: (any DiaryBiometricAccess)?

    public init(
        document: DiaryDocument, store: any DiaryStore, isNew: Bool = false,
        biometrics: (any DiaryBiometricAccess)? = nil
    ) {
        self.biometrics = biometrics
        autosave = DiaryAutosave(document: document, store: store, isNew: isNew)
        if case .plain(let payload) = document.content {
            text = payload.markdown
            location = payload.location
            weather = payload.weather
        }
    }

    public var document: DiaryDocument { autosave.document }
    public var isLocked: Bool { document.content.isEncrypted && text == nil }

    public func editTitle(_ title: String) {
        guard !isBusy else { return }
        var draft = document
        draft.metadata.title = title
        autosave.update(draft)
    }

    public func editMarkdown(_ markdown: String) {
        guard !isBusy, !isLocked else { return }
        do {
            var draft = document
            let payload = DiaryPayload(markdown: markdown, location: location, weather: weather)
            switch draft.content {
            case .plain: draft.content = .plain(payload)
            case .encrypted(let encrypted):
                guard let dataKey else { throw DiaryCryptoError.invalidParameters }
                draft.content = .encrypted(
                    try DiaryCryptor.update(payload, document: encrypted, dataKey: dataKey))
            }
            draft.schemaVersion = max(draft.schemaVersion, payload.requiredSchemaVersion)
            text = markdown
            autosave.update(draft)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func encrypt(password: String) async -> Bool {
        guard !isBusy, !document.content.isEncrypted, let markdown = text else { return false }
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }
        guard await autosave.flush() else { return saveFailed() }
        let diaryID = document.metadata.id
        let payload = DiaryPayload(markdown: markdown, location: location, weather: weather)
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try DiaryCryptor.encrypt(payload, password: password, diaryID: diaryID)
            }.value
            guard
                await autosave.commitContent(
                    .encrypted(result.document),
                    schemaVersion: max(document.schemaVersion, payload.requiredSchemaVersion))
            else { return saveFailed() }
            dataKey = result.dataKey
            lock()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    public func unlock(password: String) async -> Bool {
        guard !isBusy, isLocked, case .encrypted(let encrypted) = document.content else { return false }
        errorMessage = nil
        let revision = unlockRevision
        isBusy = true
        defer { isBusy = false }
        do {
            let unlocked = try await Task.detached(priority: .userInitiated) {
                try DiaryCryptor.unlock(encrypted, password: password)
            }.value
            guard revision == unlockRevision else { return false }
            text = unlocked.payload.markdown
            location = unlocked.payload.location
            weather = unlocked.payload.weather
            dataKey = unlocked.dataKey
            editorIdentity = UUID()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    public func lock() {
        unlockRevision += 1
        biometrics?.cancel()
        guard document.content.isEncrypted else { return }
        text = nil
        location = nil
        weather = nil
        weatherStatus = nil
        isWeatherLoading = false
        dataKey = nil
        editorIdentity = UUID()
    }

    public func exportMarkdown(to destination: URL) async -> Bool {
        guard !isBusy else { return false }
        guard !isLocked else {
            errorMessage = MarkdownExportError.locked.localizedDescription
            return false
        }
        isBusy = true
        defer { isBusy = false }
        guard await autosave.flush() else { return saveFailed() }
        // Recheck after suspension: system lock can clear plaintext while saving.
        guard let markdown = text else {
            errorMessage = MarkdownExportError.locked.localizedDescription
            return false
        }
        do {
            try await Task.detached(priority: .userInitiated) {
                try MarkdownExport.write(markdown, to: destination)
            }.value
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func saveFailed() -> Bool {
        errorMessage = autosave.status.failure ?? "日记尚未保存，请重试。"
        return false
    }
}
