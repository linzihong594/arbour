import Foundation

struct AppConfiguration {
    let libraryURL: URL
    let isDemo: Bool
    let isValidation: Bool
    let validationOutput: URL?
    let validationMode: String?
    let appearance: String?
    let validationWindowWidth: Double?
    let backupRoot: URL?
    let restoreRoot: URL?

    init(arguments: [String] = CommandLine.arguments) {
        func value(_ flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
                return nil
            }
            return arguments[index + 1]
        }
        isDemo = arguments.contains("--demo")
        let customLibrary =
            value("--library") ?? Bundle.main.object(forInfoDictionaryKey: "MacDiaryValidationLibrary")
            as? String
        isValidation = customLibrary != nil
        let width =
            value("--window-width").flatMap(Double.init)
            ?? (Bundle.main.object(forInfoDictionaryKey: "MacDiaryValidationWindowWidth") as? NSNumber)?
            .doubleValue
        validationWindowWidth =
            customLibrary != nil && width.map { (820...1600).contains($0) } == true
            ? width : nil
        appearance =
            value("--appearance") ?? Bundle.main.object(forInfoDictionaryKey: "MacDiaryValidationAppearance")
            as? String
        validationOutput = value("--validation-output").map { URL(fileURLWithPath: $0) }
        validationMode = value("--validation-mode")
        backupRoot = value("--backup-root").map { URL(fileURLWithPath: $0, isDirectory: true) }
        restoreRoot = value("--restore-root").map { URL(fileURLWithPath: $0, isDirectory: true) }
        if let custom = customLibrary {
            libraryURL = URL(fileURLWithPath: custom, isDirectory: true)
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            libraryURL = support.appendingPathComponent("MacDiary", isDirectory: true)
                .appendingPathComponent(
                    isDemo ? "DemoLibrary.noindex" : "LocalLibrary.noindex", isDirectory: true
                )
                .appendingPathComponent("Entries", isDirectory: true)
        }
    }

    var selectionKey: String { isDemo ? "demo.lastSelectedID" : "local.lastSelectedID" }
}
