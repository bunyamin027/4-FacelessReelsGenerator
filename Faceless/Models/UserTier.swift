import Foundation

// MARK: - UserTier

/// Defines the subscription tier for a user, controlling feature access and limits.
enum UserTier: String, Sendable {
    case free
    case pro

    var maxDailyVideos: Int {
        switch self {
        case .free: return 3
        case .pro: return Int.max
        }
    }

    var renderResolution: RenderResolution {
        switch self {
        case .free: return .sd720
        case .pro: return .hd1080
        }
    }

    var isWatermarkEnabled: Bool {
        switch self {
        case .free: return true
        case .pro: return false
        }
    }

    var isAutoPublishAvailable: Bool {
        switch self {
        case .free: return false
        case .pro: return true
        }
    }
}

// MARK: - RenderResolution

/// Supported render resolutions for video output.
enum RenderResolution: Sendable {
    case sd720
    case hd1080

    var size: CGSize {
        switch self {
        case .sd720: return CGSize(width: 720, height: 1280)
        case .hd1080: return CGSize(width: 1080, height: 1920)
        }
    }
}
