import Foundation

public enum SaveStatus: Equatable, Sendable {
    case saved
    case pending
    case saving
    case failed(String)

    public var label: String {
        switch self {
        case .saved: "已保存在本机"
        case .pending: "等待保存…"
        case .saving: "正在保存…"
        case .failed: "保存失败，当前编辑尚未写入磁盘"
        }
    }

    public var failure: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}
