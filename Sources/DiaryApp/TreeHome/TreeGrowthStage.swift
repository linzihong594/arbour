import Foundation

/// Genuine structural growth stages driven by diary count: trunk height, branch count, and plaque capacity
/// grow organically rather than uniformly zooming the image.
enum TreeGrowthStage: Int, CaseIterable, Identifiable, Sendable {
    case sapling = 0  // 0 entries
    case young = 1  // 1...10 entries
    case lush = 2  // 11...50 entries
    case ancient = 3  // 51...200 entries
    case giant = 4  // 201+ entries

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .sapling: "幼苗"
        case .young: "小树"
        case .lush: "繁茂大树"
        case .ancient: "参天古树"
        case .giant: "记忆巨木"
        }
    }

    var rangeHint: String {
        switch self {
        case .sapling: "0 篇"
        case .young: "1–10 篇"
        case .lush: "11–50 篇"
        case .ancient: "51–200 篇"
        case .giant: "200+ 篇"
        }
    }

    /// Actual top Y coordinate of the main trunk in canonical space (more negative = genuinely taller trunk).
    var trunkTopY: CGFloat {
        switch self {
        case .sapling: -178
        case .young: -260
        case .lush: -332
        case .ancient: -392
        case .giant: -445
        }
    }

    /// Trunk thickness multiplier (slender sapling stem -> sturdy ancient trunk).
    var trunkScale: CGFloat {
        switch self {
        case .sapling: 0.36
        case .young: 0.62
        case .lush: 0.86
        case .ancient: 1.06
        case .giant: 1.24
        }
    }

    /// Foliage richness (how many fine botanical leaves sprout on each active branch).
    var leafDensity: Double {
        switch self {
        case .sapling: 0.50
        case .young: 0.72
        case .lush: 0.92
        case .ancient: 1.08
        case .giant: 1.24
        }
    }

    /// Number of primary hanging plaque slots unlocked by this stage's branches.
    var primaryPlaqueCapacity: Int {
        switch self {
        case .sapling: 3
        case .young: 8
        case .lush: 14
        case .ancient: 18
        case .giant: 22
        }
    }

    static func forEntryCount(_ count: Int) -> TreeGrowthStage {
        switch count {
        case ...0: .sapling
        case 1...10: .young
        case 11...50: .lush
        case 51...200: .ancient
        default: .giant
        }
    }
}
