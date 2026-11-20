import DiaryCore
import Foundation
import Observation

@MainActor @Observable
public final class DiaryWorkspace {
    public internal(set) var entries: [DiarySummary] = []
    public internal(set) var trashedEntries: [DiarySummary] = []
    public internal(set) var session: DiarySession?
    public private(set) var isLoading = true
    public internal(set) var isNavigating = false
    public internal(set) var isShowingTrash = false
    public var filter = DiaryFilter()
    var selectedTrashID: UUID?
    var lastActiveID: UUID?
    public private(set) var loadIssues: [DiaryLoadIssue] = []
    public var errorMessage: String?
    let store: any DiaryStore
    private let biometrics: (any DiaryBiometricAccess)?
    private let locationProvider: (any DiaryLocationProviding)?
    private let placeNameProvider: (any DiaryPlaceNameProviding)?
    private let weatherProvider: (any DiaryWeatherProviding)?
    private var enrichmentTask: Task<Void, Never>?

    public init(
        store: any DiaryStore,
        biometrics: (any DiaryBiometricAccess)? = nil,
        locationProvider: (any DiaryLocationProviding)? = nil,
        placeNameProvider: (any DiaryPlaceNameProviding)? = nil,
        weatherProvider: (any DiaryWeatherProviding)? = nil
    ) {
        self.store = store
        self.biometrics = biometrics
        self.locationProvider = locationProvider
        self.placeNameProvider = placeNameProvider
        self.weatherProvider = weatherProvider
    }

    public var selectedID: UUID? { isShowingTrash ? selectedTrashID : session?.document.metadata.id }
    public var visibleEntries: [DiarySummary] {
        (isShowingTrash ? trashedEntries : entries).filter(filter.matches)
    }
    public var selectedTrashEntry: DiarySummary? { trashedEntries.first { $0.id == selectedTrashID } }
    public var isBusy: Bool { isLoading || isNavigating || session?.isBusy == true }
    public var selectedEntry: DiaryDocument? { session?.document }
    public var isLocked: Bool { session?.isLocked ?? false }
    public var editorIdentity: UUID? { session?.editorIdentity }
    public var location: DiaryLocation? { session?.location }
    public var weather: DiaryWeather? { session?.weather }
    public var isWeatherLoading: Bool { session?.isWeatherLoading ?? false }
    public var weatherStatus: String? { session?.weatherStatus }
    public var canRefreshWeather: Bool { session?.canRefreshWeather ?? false }
    public var markdown: String {
        get { session?.text ?? "" }
        set {
            session?.editMarkdown(newValue)
        }
    }

    public func open(preferredID: UUID? = nil, seeds: [DiaryDocument] = []) async {
        guard isLoading else { return }
        defer { isLoading = false }
        do {
            var index = try await store.index()
            if index.entries.isEmpty && index.trashedEntries.isEmpty && index.issues.isEmpty {
                for seed in seeds { _ = try await store.save(seed, expectedRevision: nil) }
                if !seeds.isEmpty { index = try await store.index() }
            }
            entries = index.entries
            trashedEntries = index.trashedEntries
            loadIssues = index.issues
            let selected = entries.first { $0.id == preferredID } ?? entries.first
            if let selected { install(try await store.load(id: selected.id)) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func select(_ id: UUID?) async {
        guard !isBusy, let id, id != selectedID else { return }
        if isShowingTrash {
            if trashedEntries.contains(where: { $0.id == id }) { selectedTrashID = id }
            return
        }
        isNavigating = true
        defer { isNavigating = false }
        guard await flush() else { return }
        do {
            let document = try await store.load(id: id)
            session?.lock()
            install(document)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func addEntry() async {
        guard !isBusy else { return }
        isNavigating = true
        defer { isNavigating = false }
        guard await flush() else { return }
        let draft = DiaryDocument(
            metadata: DiaryMetadata(title: "新的日记"),
            content: .plain(DiaryPayload(markdown: "")))
        do {
            let saved = try await store.save(draft, expectedRevision: nil)
            session?.lock()
            isShowingTrash = false
            selectedTrashID = nil
            filter = DiaryFilter()
            entries.insert(saved.summary, at: 0)
            install(saved)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func setTitle(_ title: String) {
        session?.editTitle(title)
        refreshSummary()
    }

    public func setTitle(_ title: String, from editor: UUID) {
        guard !isBusy, !isShowingTrash, editorIdentity == editor else { return }
        setTitle(title)
    }

    public func setMarkdown(_ text: String, from editor: UUID) {
        guard !isBusy, !isShowingTrash, editorIdentity == editor else { return }
        session?.editMarkdown(text)
    }

    public func encrypt(password: String) async -> Bool {
        let success = await session?.encrypt(password: password) ?? false
        refreshSummary()
        return success
    }

    public func unlock(password: String) async -> Bool {
        await session?.unlock(password: password) ?? false
    }

    public func lockSelected() {
        enrichmentTask?.cancel()
        session?.lock()
    }

    /// Requests a single fix using the injected provider; no provider means the feature is unavailable.
    @discardableResult
    public func attachCurrentLocation() async -> Bool {
        guard let locationProvider else { return false }
        return await session?.attachCurrentLocation(using: locationProvider) ?? false
    }

    @discardableResult
    public func clearLocation() -> Bool {
        session?.setLocation(nil) ?? false
    }

    @discardableResult
    public func setLocation(_ location: DiaryLocation?) -> Bool {
        let success = session?.setLocation(location) ?? false
        if success { beginEnrichment() }
        return success
    }

    /// Explicit refresh for the current diary; silently unavailable when no provider is wired.
    public func refreshWeather() {
        guard let session, let weatherProvider else { return }
        enrichmentTask?.cancel()
        enrichmentTask = Task { [weak self, weak session] in
            guard let self, let session else { return }
            await self.loadWeather(for: session, using: weatherProvider)
        }
    }

    public func unlockWithTouchID(from editor: UUID) async -> Bool {
        guard !isBusy, !isShowingTrash, editorIdentity == editor, let session else { return false }
        return await session.unlockWithTouchID()
    }

    public func flush() async -> Bool {
        guard session?.isBusy != true else {
            errorMessage = "请等待当前加密或解锁操作完成后再关闭。"
            return false
        }
        guard let session else { return !isLoading }
        let success = await session.autosave.flush()
        if !success { errorMessage = session.autosave.status.failure }
        return success
    }

    func install(_ document: DiaryDocument) {
        enrichmentTask?.cancel()
        let next = DiarySession(document: document, store: store, biometrics: biometrics)
        next.autosave.onCommit = { [weak self] _ in self?.refreshSummary() }
        session = next
        Task { [weak next] in await next?.refreshBiometricStatus() }
    }

    private func beginEnrichment() {
        enrichmentTask?.cancel()
        guard let session, let snapshot = session.location else { return }
        let nameProvider = placeNameProvider
        let weatherProvider = weatherProvider
        enrichmentTask = Task { [weak self, weak session] in
            guard let self, let session else { return }
            if let nameProvider {
                await self.loadPlaceName(for: session, using: nameProvider, snapshot: snapshot)
            }
            guard !Task.isCancelled, self.session === session, session.canRefreshWeather,
                let weatherProvider
            else { return }
            await self.loadWeather(for: session, using: weatherProvider)
        }
    }

    private func loadPlaceName(
        for session: DiarySession, using provider: any DiaryPlaceNameProviding,
        snapshot: DiaryLocation
    ) async {
        guard !Task.isCancelled, self.session === session,
            let name = try? await provider.placeName(for: snapshot), !Task.isCancelled
        else { return }
        _ = session.applyPlaceName(name, for: snapshot)
    }

    private func loadWeather(for session: DiarySession, using provider: any DiaryWeatherProviding)
        async
    {
        guard !Task.isCancelled, self.session === session else { return }
        _ = await session.refreshWeather(using: provider)
    }

    private func refreshSummary() {
        guard let session, let index = entries.firstIndex(where: { $0.id == session.document.metadata.id })
        else { return }
        entries[index] = session.document.summary
    }
}
