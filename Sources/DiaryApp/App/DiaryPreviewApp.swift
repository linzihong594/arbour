import DiaryCore
import DiaryPlatform
import DiaryState
import SwiftUI

@main
struct DiaryPreviewApp: App {
    @NSApplicationDelegateAdaptor(DiaryAppDelegate.self) private var appDelegate
    @ViewState<DiaryWorkspace> private var workspace: DiaryWorkspace
    private let configuration: AppConfiguration

    init() {
        let configuration = AppConfiguration()
        self.configuration = configuration
        _workspace = ViewState(
            wrappedValue: DiaryWorkspace(
                store: DiaryRepository(directory: configuration.libraryURL),
                biometrics: SystemBiometricAccess(),
                locationProvider: SystemLocationProvider(),
                placeNameProvider: SystemPlaceNameProvider(),
                weatherProvider: OpenMeteoWeatherProvider()))
    }

    var body: some Scene {
        Window(
            configuration.isDemo ? "栖木 · 示例库" : "栖木",
            id: configuration.isValidation ? "validation-workspace" : "workspace"
        ) {
            WorkspaceView(workspace: workspace, configuration: configuration)
                .frame(minWidth: 820, minHeight: 580)
                .preferredColorScheme(
                    configuration.appearance == "light"
                        ? .light : configuration.appearance == "dark" ? .dark : nil
                )
                .task {
                    appDelegate.workspace = workspace
                    let preferred =
                        configuration.isValidation
                        ? nil
                        : UserDefaults.standard.string(forKey: configuration.selectionKey).flatMap(
                            UUID.init(uuidString:))
                    await workspace.open(
                        preferredID: preferred, seeds: configuration.isDemo ? DiarySamples.documents() : [])
                    await ValidationRun.run(configuration: configuration, workspace: workspace)
                }
                .onChange(of: workspace.selectedID) { _, id in
                    if !configuration.isValidation {
                        UserDefaults.standard.set(id?.uuidString, forKey: configuration.selectionKey)
                    }
                }
        }
        .defaultSize(width: 1080, height: 760)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建日记") { Task { await workspace.addEntry() } }
                    .keyboardShortcut("n", modifiers: .command).disabled(workspace.isBusy)
            }
            CommandGroup(replacing: .saveItem) {
                Button("保存日记") { Task { await workspace.flush() } }
                    .keyboardShortcut("s", modifiers: .command).disabled(workspace.isBusy)
            }
        }
    }
}
