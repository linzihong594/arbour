import Foundation

public enum DiaryLocationRequestError: LocalizedError, Equatable, Sendable {
    case denied
    case restricted
    case unavailable
    case timeout
    case stale

    public var errorDescription: String? {
        switch self {
        case .denied: "定位权限被拒绝。可在系统设置中允许后重试；日记仍可继续写。"
        case .restricted: "系统限制了定位。可以继续写日记或在地图上手动选点。"
        case .unavailable: "暂时无法获取当前位置。可以稍后重试或手动选点。"
        case .timeout: "定位请求超时，已停止本次定位。可以重试或手动选点。"
        case .stale: "定位结果过于陈旧，未采用。可以重试或手动选点。"
        }
    }
}

/// One explicit fix per request. Implementations must stop location updates before returning.
@MainActor
public protocol DiaryLocationProviding: Sendable {
    func requestCurrentLocation() async throws -> DiaryLocation
}
