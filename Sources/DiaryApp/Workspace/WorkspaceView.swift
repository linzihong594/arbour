import AppKit
import DiaryState
import SwiftUI

struct WorkspaceView: View {
    let workspace: DiaryWorkspace
    let configuration: AppConfiguration
    @ViewState<Bool> private var showsPassword = false
    @ViewState<Bool> private var showsMapPicker = false
    @ViewState<Bool> private var showsCapabilities = false
    @ViewState<Bool> private var showsBackup = false
    @ViewState<Bool> private var showsTreeHome: Bool
    @ViewState<Bool> private var showsDrawer = false
    @ViewState<UUID?> private var newlyHungID = nil
    @ViewState<BackupController> private var backup: BackupController
    @ViewState<TreeSceneWeatherController> private var sceneWeather: TreeSceneWeatherController

    init(workspace: DiaryWorkspace, configuration: AppConfiguration) {
        self.workspace = workspace
        self.configuration = configuration
        _showsTreeHome = ViewState(wrappedValue: !configuration.isValidation)
        _backup = ViewState(
            wrappedValue: BackupController(
                libraryURL: configuration.libraryURL, isValidation: configuration.isValidation))
        _sceneWeather = ViewState(
            wrappedValue: TreeSceneWeatherController(isValidation: configuration.isValidation))
    }

    var body: some View {
        Group {
            if showsTreeHome {
                TreeHomeView(
                    workspace: workspace,
                    weather: sceneWeather,
                    isDemo: configuration.isDemo,
                    newlyHungID: $newlyHungID,
                    openEntry: { id in
                        Task {
                            if workspace.isShowingTrash {
                                await workspace.showTrash(false)
                            }
                            await workspace.select(id)
                            showsDrawer = false
                            withAnimation(.easeInOut(duration: 0.22)) {
                                showsTreeHome = false
                            }
                        }
                    },
                    lockEntry: { id in
                        Task {
                            if workspace.isShowingTrash {
                                await workspace.showTrash(false)
                            }
                            await workspace.select(id)
                            showsDrawer = false
                            withAnimation(.easeInOut(duration: 0.22)) {
                                showsTreeHome = false
                            }
                            showsPassword = true
                        }
                    },
                    exportEntry: { id in
                        Task {
                            if workspace.isShowingTrash {
                                await workspace.showTrash(false)
                            }
                            await workspace.select(id)
                            guard !workspace.isLocked, workspace.selectedID == id else { return }
                            MarkdownExportPanel.present(
                                for: workspace,
                                initialDirectory: configuration.isValidation
                                    ? configuration.libraryURL.deletingLastPathComponent() : nil)
                        }
                    },
                    createEntry: {
                        Task {
                            await workspace.addEntry()
                            newlyHungID = workspace.selectedID
                            showsDrawer = false
                            withAnimation(.easeInOut(duration: 0.22)) {
                                showsTreeHome = false
                            }
                        }
                    },
                    openListWorkspace: {
                        showsDrawer = true
                        withAnimation(.easeInOut(duration: 0.22)) {
                            showsTreeHome = false
                        }
                    },
                    openBackup: { showsBackup = true },
                    openCapabilities: { showsCapabilities = true }
                )
            } else {
                JournalReaderView(
                    workspace: workspace,
                    configuration: configuration,
                    weather: sceneWeather,
                    showsDrawer: $showsDrawer,
                    returnToTree: {
                        Task {
                            guard await workspace.flush() else { return }
                            showsDrawer = false
                            withAnimation(.easeInOut(duration: 0.22)) {
                                showsTreeHome = true
                            }
                        }
                    },
                    openPassword: { showsPassword = true },
                    openMapPicker: { showsMapPicker = true },
                    openBackup: { showsBackup = true },
                    openCapabilities: { showsCapabilities = true }
                )
            }
        }
        .tint(DiaryStyle.accent)
        .background(WindowSaveGuard(workspace: workspace).frame(width: 0, height: 0))
        .sheet(isPresented: $showsPassword) {
            PasswordSheet(workspace: workspace)
        }
        .sheet(isPresented: $showsMapPicker) {
            LocationMapPicker(initial: workspace.location) { location in
                _ = workspace.setLocation(location)
            }
        }
        .sheet(isPresented: $showsCapabilities) {
            CapabilityView()
        }
        .sheet(isPresented: $showsBackup) {
            BackupView(controller: backup)
        }
        .task {
            if !configuration.isValidation { await backup.load() }
        }
        .onChange(of: workspace.session?.autosave.status) { _, status in
            if status == .saved { backup.noteSaveCompleted() }
        }
        .onChange(of: workspace.entries.count) { oldCount, newCount in
            if !workspace.isLoading && newCount > oldCount {
                newlyHungID = workspace.entries.first?.id
                if showsTreeHome {
                    showsDrawer = false
                    withAnimation(.easeInOut(duration: 0.22)) {
                        showsTreeHome = false
                    }
                }
            }
        }
        .alert(
            "暂时无法完成",
            isPresented: Binding(
                get: { errorMessage != nil && !showsPassword },
                set: { if !$0 { clearError() } }
            )
        ) {
            Button("好", role: .cancel) { clearError() }
        } message: {
            Text(errorMessage ?? "")
        }
        .onReceive(
            NSWorkspace.shared.notificationCenter.publisher(
                for: NSWorkspace.sessionDidResignActiveNotification)
        ) { _ in
            lockForSystemEvent()
        }
        .onReceive(
            DistributedNotificationCenter.default().publisher(
                for: Notification.Name("com.apple.screenIsLocked"))
        ) { _ in
            lockForSystemEvent()
        }
    }

    private var errorMessage: String? { workspace.errorMessage ?? workspace.session?.errorMessage }
    private func lockForSystemEvent() {
        showsPassword = false
        workspace.lockSelected()
    }
    private func clearError() {
        workspace.errorMessage = nil
        workspace.session?.errorMessage = nil
    }
}
