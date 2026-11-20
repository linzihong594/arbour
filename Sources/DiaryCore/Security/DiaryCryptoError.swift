import Foundation

public enum DiaryCryptoError: LocalizedError, Equatable {
    case passwordTooShort
    case unsupportedFormat
    case invalidParameters
    case authenticationFailed
    case keyDerivationFailed
    case randomGenerationFailed

    public var errorDescription: String? {
        switch self {
        case .passwordTooShort:
            "请使用至少 8 个字符的密码。"
        case .unsupportedFormat:
            "此加密格式尚不受支持。请保留文件并使用兼容版本打开。"
        case .invalidParameters:
            "加密文件参数无效，无法解密。"
        case .authenticationFailed:
            "密码不正确，或加密文件已损坏。"
        case .keyDerivationFailed:
            "无法生成密码密钥。"
        case .randomGenerationFailed:
            "系统无法生成安全随机数。"
        }
    }
}
