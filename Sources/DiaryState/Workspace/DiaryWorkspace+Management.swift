import DiaryCore
import Foundation

extension DiaryWorkspace {
    public func showTrash(_ showing: Bool) async {
        guard !isBusy, showing != isShowingTrash else { return }
        isNavigating = true
        defer { isNavigating = false }
        guard await flush() else { return }
        if showing { lastActiveID = selectedID }
        session?.lock()
        session = nil
        isShowingTrash = showing
        if showing {
            selectedTrashID = visibleEntries.first?.id
        } else if let next = visibleEntries.first(where: { $0.id == lastActiveID }) ?? visibleEntries.first {
            do { install(try await store.load(id: next.id)) } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    public func trashSelected() async {
        guard !isBusy, !isShowingTrash, session != nil else { return }
        isNavigating = true
        defer { isNavigating = false }
        guard await flush(), let document = session?.document else { return }
        do {
            let summary = try await store.trash(
                id: document.metadata.id, expectedRevision: document.metadata.revision)
            session?.lock()
            session = nil
            entries.removeAll { $0.id == summary.id }
            trashedEntries.append(summary)
            trashedEntries.sort(by: DiarySummary.newestFirst)
            if let next = visibleEntries.first { install(try await store.load(id: next.id)) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func restoreSelected() async {
        guard !isBusy, isShowingTrash, let summary = selectedTrashEntry else { return }
        isNavigating = true
        defer { isNavigating = false }
        do {
            let restored = try await store.restore(
                id: summary.id, expectedRevision: summary.metadata.revision)
            trashedEntries.removeAll { $0.id == summary.id }
            entries.append(restored.summary)
            entries.sort(by: DiarySummary.newestFirst)
            selectedTrashID = nil
            isShowingTrash = false
            install(restored)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    public func exportMarkdown(id: UUID, to destination: URL) async -> Bool {
        guard !isBusy, !isShowingTrash, selectedID == id, let session else { return false }
        let success = await session.exportMarkdown(to: destination)
        if !success { errorMessage = session.errorMessage }
        return success
    }
}
