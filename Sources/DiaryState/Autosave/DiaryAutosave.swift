import DiaryCore
import Foundation
import Observation

/// Coalesces drafts and serializes writes. A failed save never discards the current draft.
@MainActor @Observable
public final class DiaryAutosave {
    public private(set) var document: DiaryDocument
    public private(set) var status: SaveStatus
    public var onCommit: (@MainActor (DiaryDocument) -> Void)?

    private let store: any DiaryStore
    private let delay: Duration
    private var storedRevision: UInt64?
    private var generation = 0
    private var savedGeneration = 0
    private var debounce: Task<Void, Never>?
    private var flight: (id: UUID, task: Task<Bool, Never>)?

    public init(
        document: DiaryDocument, store: any DiaryStore, isNew: Bool = false,
        delay: Duration = .milliseconds(350)
    ) {
        self.document = document
        self.store = store
        self.delay = delay
        storedRevision = isNew ? nil : document.metadata.revision
        status = isNew ? .pending : .saved
        generation = isNew ? 1 : 0
    }

    public func update(_ document: DiaryDocument) {
        guard document != self.document else { return }
        self.document = document
        self.document.metadata.updatedAt = max(
            DiaryMetadata.timestamp(.now), document.metadata.updatedAt, document.metadata.createdAt)
        generation += 1
        status = .pending
        debounce?.cancel()
        debounce = Task { [weak self, delay] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard !Task.isCancelled else { return }
            _ = await self?.flush()
        }
    }

    @discardableResult
    public func flush() async -> Bool {
        debounce?.cancel()
        debounce = nil
        if let existing = flight {
            let success = await existing.task.value
            if flight?.id == existing.id { flight = nil }
            guard success else { return false }
            return await flush()
        }
        guard generation != savedGeneration else {
            status = .saved
            return true
        }
        let id = UUID()
        let task = Task { await drainChanges() }
        flight = (id, task)
        let success = await task.value
        if flight?.id == id { flight = nil }
        return success
    }

    /// The session disables editing during this transaction. Publish encryption only after disk commit.
    func commitContent(_ content: DiaryContent, schemaVersion: Int? = nil) async -> Bool {
        guard await flush() else { return false }
        var candidate = document
        candidate.content = content
        if let schemaVersion { candidate.schemaVersion = max(candidate.schemaVersion, schemaVersion) }
        candidate.metadata.updatedAt = max(DiaryMetadata.timestamp(.now), candidate.metadata.updatedAt)
        status = .saving
        do {
            let committed = try await store.save(candidate, expectedRevision: storedRevision)
            document = committed
            storedRevision = committed.metadata.revision
            status = .saved
            onCommit?(committed)
            return true
        } catch {
            status = .failed(error.localizedDescription)
            return false
        }
    }

    private func drainChanges() async -> Bool {
        while generation != savedGeneration {
            let snapshot = document
            let savingGeneration = generation
            status = .saving
            do {
                let committed = try await store.save(snapshot, expectedRevision: storedRevision)
                storedRevision = committed.metadata.revision
                document.metadata.revision = committed.metadata.revision
                savedGeneration = savingGeneration
                onCommit?(committed)
            } catch {
                status = .failed(error.localizedDescription)
                return false
            }
        }
        status = .saved
        return true
    }
}
