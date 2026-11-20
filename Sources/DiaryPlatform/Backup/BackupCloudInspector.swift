import Foundation

/// What the filesystem can prove about a snapshot's iCloud state.
///
/// A local write is never reported as an upload: the state only becomes `uploaded` when every
/// regular file in the snapshot reports `ubiquitousItemIsUploaded`.
public enum BackupCloudState: String, Equatable, Sendable {
    case localOnly
    case waitingForUpload
    case uploaded
    case unknown

    public var label: String {
        switch self {
        case .localOnly: "仅保存在本地"
        case .waitingForUpload: "等待 iCloud 上传"
        case .uploaded: "已上传到 iCloud"
        case .unknown: "云端状态未知"
        }
    }
}

public enum BackupCloudInspector {
    public static func state(of directory: URL) -> BackupCloudState {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard
            fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else { return .unknown }

        let keys: Set<URLResourceKey> = [
            .isUbiquitousItemKey, .ubiquitousItemIsUploadedKey, .ubiquitousItemIsUploadingKey,
        ]
        guard let rootValues = try? directory.resourceValues(forKeys: keys) else { return .unknown }
        guard rootValues.isUbiquitousItem == true else { return .localOnly }

        guard
            let enumerator = fileManager.enumerator(
                at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]
            )
        else { return .unknown }

        var sawRegularFile = false
        for case let fileURL as URL in enumerator {
            guard
                let values = try? fileURL.resourceValues(forKeys: keys),
                values.isRegularFile == true
            else { continue }
            sawRegularFile = true
            guard values.isUbiquitousItem == true else { return .waitingForUpload }
            if values.ubiquitousItemIsUploaded != true { return .waitingForUpload }
        }
        return sawRegularFile ? .uploaded : .waitingForUpload
    }
}
