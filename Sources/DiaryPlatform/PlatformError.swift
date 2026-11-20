import Foundation
import Security

public enum PlatformError: LocalizedError {
    case keychain(OSStatus)
    case message(String)

    public var errorDescription: String? {
        switch self {
        case .keychain(let status):
            if status == errSecMissingEntitlement {
                return "当前签名缺少 Keychain 所需授权（\(status)）。密码加密仍可使用，Touch ID 需要完成签名配置后验证。"
            }
            if status == errSecUserCanceled || status == errSecAuthFailed {
                return "指纹验证已取消或未通过，密钥未释放。"
            }
            if status == errSecItemNotFound {
                return "这篇日记的 Touch ID 密钥不存在或已失效，请用日记密码解锁后重新启用。"
            }
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "未知错误"
            return "Keychain 错误（\(status)）：\(detail)"
        case .message(let message):
            return message
        }
    }
}
