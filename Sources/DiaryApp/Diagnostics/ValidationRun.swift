import AppKit
import DiaryPlatform
import DiaryState
import Foundation

/// Opt-in instrumentation for a caller-supplied synthetic library; never runs for the normal library.
@MainActor
enum ValidationRun {
    static func run(configuration: AppConfiguration, workspace: DiaryWorkspace) async {
        guard configuration.isValidation else { return }
        if let width = configuration.validationWindowWidth {
            NSApp.windows.first(where: { $0.contentView != nil })?.setContentSize(
                NSSize(width: width, height: 580))
        }
        if configuration.validationMode == "reset-backup" {
            let defaults = UserDefaults.standard
            defaults.removeObject(forKey: BackupController.bookmarkDefaultsKey)
            defaults.removeObject(forKey: BackupController.autoBackupDefaultsKey)
            exit(EXIT_SUCCESS)
        }
        guard let output = configuration.validationOutput else { return }
        if configuration.validationMode == "keychain" {
            do {
                try await KeychainValidation.run(output: output)
                exit(EXIT_SUCCESS)
            } catch {
                FileHandle.standardError.write(
                    Data("Keychain validation failed: \(error.localizedDescription)\n".utf8))
                exit(EXIT_FAILURE)
            }
        }
        if configuration.validationMode == "backup" {
            guard let backupRoot = configuration.backupRoot, let restoreRoot = configuration.restoreRoot
            else {
                FileHandle.standardError.write(
                    Data("Backup validation requires --backup-root and --restore-root\n".utf8))
                exit(EXIT_FAILURE)
            }
            do {
                _ = await workspace.flush()
                try await BackupValidation.run(
                    libraryURL: configuration.libraryURL, backupRoot: backupRoot,
                    restoreRoot: restoreRoot, output: output)
                exit(EXIT_SUCCESS)
            } catch {
                FileHandle.standardError.write(
                    Data("Backup validation failed: \(error.localizedDescription)\n".utf8))
                exit(EXIT_FAILURE)
            }
        }
        if configuration.validationMode == "privacy" {
            do {
                try await WorkspacePrivacyValidation.run(workspace: workspace, output: output)
                let saved = await workspace.flush()
                workspace.lockSelected()
                exit(saved ? EXIT_SUCCESS : EXIT_FAILURE)
            } catch {
                FileHandle.standardError.write(
                    Data("Privacy validation failed: \(error.localizedDescription)\n".utf8))
                exit(EXIT_FAILURE)
            }
        }
        do {
            try await Task.sleep(for: .milliseconds(50))
            for _ in 0..<100 {
                if NSApplication.shared.windows.contains(where: { $0.contentView.map(containsEditor) == true }
                ) {
                    break
                }
                try await Task.sleep(for: .milliseconds(20))
            }
            let hasEditor = NSApplication.shared.windows.contains {
                $0.contentView.map(containsEditor) == true
            }
            guard hasEditor else { throw PlatformError.message("Native editor did not become ready") }
            if let window = NSApplication.shared.windows.first(where: { $0.contentView != nil }) {
                window.contentView?.layoutSubtreeIfNeeded()
                window.isRestorable = false
                window.setFrameAutosaveName("")
                window.setFrameOrigin(NSPoint(x: -30000, y: -30000))
            }
            let initial = try ProcessMetrics.current()
            let started = ContinuousClock.now
            let ready: [String: Any] = [
                "entries": workspace.entries.count,
                "hasEditor": hasEditor,
                "pid": ProcessInfo.processInfo.processIdentifier,
            ]
            try JSONSerialization.data(withJSONObject: ready).write(
                to: output.appendingPathExtension("ready.json"), options: .atomic)
            if configuration.validationMode == "idle" { try await Task.sleep(for: .seconds(60)) }
            let duration = started.duration(to: .now).components
            let elapsed = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
            let final = try ProcessMetrics.current()
            let report: [String: Any] = [
                "entries": workspace.entries.count,
                "physicalFootprintBytes": final.physicalFootprintBytes,
                "initialPhysicalFootprintBytes": initial.physicalFootprintBytes,
                "idleSeconds": elapsed,
                "averageCPUPercent": elapsed > 0
                    ? (final.cpuSeconds - initial.cpuSeconds) / elapsed * 100 : 0,
                "metric":
                    "TASK_VM_INFO.phys_footprint and getrusage; application process, no custom child processes",
                "saveStatus": workspace.session?.autosave.status.label ?? "no session",
            ]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: output, options: .atomic)
        } catch {
            FileHandle.standardError.write(Data("Validation failed: \(error.localizedDescription)\n".utf8))
        }
        // This opt-in probe runs inside a SwiftUI task. Entering AppKit's terminate-later
        // modal loop here can block the actor needed to answer the termination request.
        let saved = await workspace.flush()
        workspace.lockSelected()
        exit(saved ? EXIT_SUCCESS : EXIT_FAILURE)
    }

    private static func containsEditor(_ view: NSView) -> Bool {
        if let text = view as? NSTextView, !text.isFieldEditor { return true }
        return view.subviews.contains(where: containsEditor)
    }
}
