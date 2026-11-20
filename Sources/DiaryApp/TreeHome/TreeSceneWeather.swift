import CoreLocation
import DiaryCore
import DiaryPlatform
import Foundation
import Observation
import SwiftUI

enum TreeWeatherKind: String, CaseIterable, Identifiable, Sendable {
    case clear
    case cloudy
    case fog
    case rain
    case snow
    case thunderstorm

    var id: String { rawValue }

    var label: String {
        switch self {
        case .clear: "晴朗"
        case .cloudy: "多云"
        case .fog: "薄雾"
        case .rain: "雨天"
        case .snow: "降雪"
        case .thunderstorm: "雷雨"
        }
    }

    var symbolName: String {
        switch self {
        case .clear: "sun.max.fill"
        case .cloudy: "cloud.sun.fill"
        case .fog: "cloud.fog.fill"
        case .rain: "cloud.rain.fill"
        case .snow: "cloud.snow.fill"
        case .thunderstorm: "cloud.bolt.rain.fill"
        }
    }

    var defaultWindSpeedKmh: Double {
        switch self {
        case .clear: 8
        case .cloudy: 12
        case .fog: 5
        case .rain: 19
        case .snow: 12
        case .thunderstorm: 30
        }
    }

    static func from(weatherCode: Int) -> TreeWeatherKind {
        switch weatherCode {
        case 0, 1: .clear
        case 2, 3: .cloudy
        case 45, 48: .fog
        case 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82: .rain
        case 71, 73, 75, 77, 85, 86: .snow
        case 95, 96, 99: .thunderstorm
        default: .cloudy
        }
    }
}

enum TreeSeason: String, CaseIterable, Identifiable, Sendable {
    case spring
    case summer
    case autumn
    case winter

    var id: String { rawValue }

    var label: String {
        switch self {
        case .spring: "春 · 新绿樱粉"
        case .summer: "夏 · 苍翠浓荫"
        case .autumn: "秋 · 金杏枫红"
        case .winter: "冬 · 清霜雪枝"
        }
    }

    var shortLabel: String {
        switch self {
        case .spring: "春"
        case .summer: "夏"
        case .autumn: "秋"
        case .winter: "冬"
        }
    }

    static var current: TreeSeason {
        let month = Calendar.current.component(.month, from: .now)
        switch month {
        case 3...5: return .spring
        case 6...8: return .summer
        case 9...11: return .autumn
        default: return .winter
        }
    }
}

enum TreeTimeOfDay: String, Sendable {
    case dawn  // 05:00 - 08:59
    case day  // 09:00 - 16:59
    case dusk  // 17:00 - 19:59
    case night  // 20:00 - 04:59

    static var current: TreeTimeOfDay {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5...8: return .dawn
        case 9...16: return .day
        case 17...19: return .dusk
        default: return .night
        }
    }

    /// Normalized (x, y) position of the sun/moon across the upper sky arc (kept below the top bar).
    var celestialPosition: CGPoint {
        switch self {
        case .dawn: CGPoint(x: 0.24, y: 0.25)
        case .day: CGPoint(x: 0.76, y: 0.23)
        case .dusk: CGPoint(x: 0.84, y: 0.27)
        case .night: CGPoint(x: 0.80, y: 0.24)
        }
    }
}

struct TreeAtmospherePalette {
    let skyTop: Color
    let skyMid: Color
    let skyBottom: Color
    let celestialColor: Color
    let cloudColor: Color
    let hillFar: Color
    let hillNear: Color
    let trunkDark: Color
    let trunkLight: Color
    let leafBack: Color
    let leafMid: Color
    let leafFront: Color
    let leafAccent: Color
    let precipitationColor: Color
    let plaqueBackground: Color
    let plaqueBorder: Color
    let plaqueText: Color
    let plaqueDate: Color

    static func resolve(
        kind: TreeWeatherKind,
        season: TreeSeason = .current,
        timeOfDay: TreeTimeOfDay = .current,
        dark: Bool
    ) -> TreeAtmospherePalette {
        let base = dark ? darkPalette(for: kind) : lightPalette(for: kind)
        return applyAtmosphere(base: base, kind: kind, season: season, timeOfDay: timeOfDay, dark: dark)
    }

    /// Modulates foliage by season and gently warms/cools the sky for dawn/dusk while preserving weather identity.
    private static func applyAtmosphere(
        base: TreeAtmospherePalette,
        kind: TreeWeatherKind,
        season: TreeSeason,
        timeOfDay: TreeTimeOfDay,
        dark: Bool
    ) -> TreeAtmospherePalette {
        let leaves: (Color, Color, Color, Color)
        switch season {
        case .summer:
            leaves = (base.leafBack, base.leafMid, base.leafFront, base.leafAccent)
        case .spring:
            if dark {
                leaves = (
                    Color(red: 0.14, green: 0.26, blue: 0.18),
                    Color(red: 0.23, green: 0.39, blue: 0.24),
                    Color(red: 0.36, green: 0.52, blue: 0.31),
                    Color(red: 0.82, green: 0.62, blue: 0.68)  // soft moonlit cherry-blossom accent
                )
            } else {
                leaves = (
                    Color(red: 0.34, green: 0.54, blue: 0.33),
                    Color(red: 0.48, green: 0.68, blue: 0.39),
                    Color(red: 0.64, green: 0.79, blue: 0.48),
                    Color(red: 0.96, green: 0.77, blue: 0.81)  // delicate spring blossom petals
                )
            }
        case .autumn:
            if dark {
                leaves = (
                    Color(red: 0.28, green: 0.17, blue: 0.12),
                    Color(red: 0.45, green: 0.26, blue: 0.14),
                    Color(red: 0.62, green: 0.39, blue: 0.18),
                    Color(red: 0.78, green: 0.55, blue: 0.22)  // golden ginkgo & maple
                )
            } else {
                leaves = (
                    Color(red: 0.52, green: 0.31, blue: 0.17),
                    Color(red: 0.73, green: 0.44, blue: 0.18),
                    Color(red: 0.87, green: 0.63, blue: 0.23),
                    Color(red: 0.83, green: 0.36, blue: 0.22)  // warm maple crimson accent
                )
            }
        case .winter:
            if dark {
                leaves = (
                    Color(red: 0.14, green: 0.21, blue: 0.25),
                    Color(red: 0.22, green: 0.31, blue: 0.35),
                    Color(red: 0.36, green: 0.46, blue: 0.51),
                    Color(red: 0.80, green: 0.86, blue: 0.92)  // crisp frost tips
                )
            } else {
                leaves = (
                    Color(red: 0.34, green: 0.45, blue: 0.48),
                    Color(red: 0.48, green: 0.59, blue: 0.62),
                    Color(red: 0.66, green: 0.76, blue: 0.79),
                    Color(red: 0.92, green: 0.95, blue: 0.98)  // frosted winter tips
                )
            }
        }

        // Gentle sky tint for dawn/dusk in clear & cloudy light mode.
        var skyTop = base.skyTop
        var skyMid = base.skyMid
        var skyBottom = base.skyBottom
        var celestial = base.celestialColor
        if !dark && (kind == .clear || kind == .cloudy) {
            if timeOfDay == .dawn {
                skyTop = Color(red: 0.68, green: 0.76, blue: 0.88)
                skyMid = Color(red: 0.91, green: 0.84, blue: 0.84)
                skyBottom = Color(red: 0.99, green: 0.92, blue: 0.83)
                celestial = Color(red: 1.0, green: 0.87, blue: 0.68)
            } else if timeOfDay == .dusk {
                skyTop = Color(red: 0.52, green: 0.59, blue: 0.75)
                skyMid = Color(red: 0.85, green: 0.72, blue: 0.66)
                skyBottom = Color(red: 0.98, green: 0.84, blue: 0.69)
                celestial = Color(red: 1.0, green: 0.76, blue: 0.52)
            }
        }

        return TreeAtmospherePalette(
            skyTop: skyTop,
            skyMid: skyMid,
            skyBottom: skyBottom,
            celestialColor: celestial,
            cloudColor: base.cloudColor,
            hillFar: base.hillFar,
            hillNear: base.hillNear,
            trunkDark: base.trunkDark,
            trunkLight: base.trunkLight,
            leafBack: leaves.0,
            leafMid: leaves.1,
            leafFront: leaves.2,
            leafAccent: leaves.3,
            precipitationColor: base.precipitationColor,
            plaqueBackground: base.plaqueBackground,
            plaqueBorder: base.plaqueBorder,
            plaqueText: base.plaqueText,
            plaqueDate: base.plaqueDate
        )
    }

    private static func lightPalette(for kind: TreeWeatherKind) -> TreeAtmospherePalette {
        switch kind {
        case .clear:
            return TreeAtmospherePalette(
                skyTop: Color(red: 0.72, green: 0.85, blue: 0.94),
                skyMid: Color(red: 0.88, green: 0.93, blue: 0.95),
                skyBottom: Color(red: 0.98, green: 0.95, blue: 0.88),
                celestialColor: Color(red: 1.0, green: 0.93, blue: 0.72),
                cloudColor: Color.white.opacity(0.65),
                hillFar: Color(red: 0.73, green: 0.81, blue: 0.72),
                hillNear: Color(red: 0.62, green: 0.73, blue: 0.58),
                trunkDark: Color(red: 0.35, green: 0.26, blue: 0.20),
                trunkLight: Color(red: 0.48, green: 0.37, blue: 0.29),
                leafBack: Color(red: 0.30, green: 0.46, blue: 0.31),
                leafMid: Color(red: 0.41, green: 0.58, blue: 0.36),
                leafFront: Color(red: 0.55, green: 0.70, blue: 0.43),
                leafAccent: Color(red: 0.74, green: 0.82, blue: 0.52),
                precipitationColor: Color(red: 1.0, green: 0.95, blue: 0.78),
                plaqueBackground: Color(red: 0.99, green: 0.96, blue: 0.90),
                plaqueBorder: Color(red: 0.74, green: 0.64, blue: 0.49),
                plaqueText: Color(red: 0.22, green: 0.19, blue: 0.15),
                plaqueDate: Color(red: 0.52, green: 0.45, blue: 0.35)
            )
        case .cloudy:
            return TreeAtmospherePalette(
                skyTop: Color(red: 0.75, green: 0.80, blue: 0.85),
                skyMid: Color(red: 0.85, green: 0.88, blue: 0.90),
                skyBottom: Color(red: 0.93, green: 0.93, blue: 0.91),
                celestialColor: Color(red: 0.98, green: 0.96, blue: 0.89),
                cloudColor: Color.white.opacity(0.75),
                hillFar: Color(red: 0.70, green: 0.75, blue: 0.72),
                hillNear: Color(red: 0.58, green: 0.66, blue: 0.59),
                trunkDark: Color(red: 0.34, green: 0.27, blue: 0.23),
                trunkLight: Color(red: 0.45, green: 0.38, blue: 0.33),
                leafBack: Color(red: 0.30, green: 0.43, blue: 0.34),
                leafMid: Color(red: 0.40, green: 0.53, blue: 0.41),
                leafFront: Color(red: 0.51, green: 0.63, blue: 0.49),
                leafAccent: Color(red: 0.66, green: 0.74, blue: 0.60),
                precipitationColor: Color.white.opacity(0.5),
                plaqueBackground: Color(red: 0.98, green: 0.96, blue: 0.92),
                plaqueBorder: Color(red: 0.70, green: 0.65, blue: 0.57),
                plaqueText: Color(red: 0.21, green: 0.20, blue: 0.18),
                plaqueDate: Color(red: 0.48, green: 0.46, blue: 0.41)
            )
        case .fog:
            return TreeAtmospherePalette(
                skyTop: Color(red: 0.82, green: 0.85, blue: 0.86),
                skyMid: Color(red: 0.89, green: 0.91, blue: 0.91),
                skyBottom: Color(red: 0.94, green: 0.95, blue: 0.94),
                celestialColor: Color.white.opacity(0.7),
                cloudColor: Color.white.opacity(0.68),
                hillFar: Color(red: 0.76, green: 0.80, blue: 0.79),
                hillNear: Color(red: 0.66, green: 0.72, blue: 0.69),
                trunkDark: Color(red: 0.38, green: 0.34, blue: 0.31),
                trunkLight: Color(red: 0.49, green: 0.45, blue: 0.42),
                leafBack: Color(red: 0.38, green: 0.48, blue: 0.44),
                leafMid: Color(red: 0.48, green: 0.58, blue: 0.53),
                leafFront: Color(red: 0.59, green: 0.68, blue: 0.62),
                leafAccent: Color(red: 0.73, green: 0.79, blue: 0.74),
                precipitationColor: Color.white.opacity(0.42),
                plaqueBackground: Color(red: 0.98, green: 0.97, blue: 0.94),
                plaqueBorder: Color(red: 0.73, green: 0.71, blue: 0.66),
                plaqueText: Color(red: 0.23, green: 0.23, blue: 0.22),
                plaqueDate: Color(red: 0.50, green: 0.50, blue: 0.48)
            )
        case .rain:
            return TreeAtmospherePalette(
                skyTop: Color(red: 0.54, green: 0.63, blue: 0.72),
                skyMid: Color(red: 0.67, green: 0.74, blue: 0.80),
                skyBottom: Color(red: 0.81, green: 0.85, blue: 0.88),
                celestialColor: Color.white.opacity(0.35),
                cloudColor: Color(red: 0.76, green: 0.81, blue: 0.86).opacity(0.85),
                hillFar: Color(red: 0.54, green: 0.64, blue: 0.63),
                hillNear: Color(red: 0.43, green: 0.55, blue: 0.51),
                trunkDark: Color(red: 0.27, green: 0.22, blue: 0.19),
                trunkLight: Color(red: 0.37, green: 0.31, blue: 0.27),
                leafBack: Color(red: 0.21, green: 0.36, blue: 0.32),
                leafMid: Color(red: 0.28, green: 0.45, blue: 0.38),
                leafFront: Color(red: 0.37, green: 0.55, blue: 0.45),
                leafAccent: Color(red: 0.50, green: 0.66, blue: 0.56),
                precipitationColor: Color(red: 0.86, green: 0.93, blue: 0.99),
                plaqueBackground: Color(red: 0.96, green: 0.95, blue: 0.91),
                plaqueBorder: Color(red: 0.62, green: 0.61, blue: 0.56),
                plaqueText: Color(red: 0.19, green: 0.20, blue: 0.20),
                plaqueDate: Color(red: 0.44, green: 0.46, blue: 0.46)
            )
        case .snow:
            return TreeAtmospherePalette(
                skyTop: Color(red: 0.72, green: 0.80, blue: 0.88),
                skyMid: Color(red: 0.84, green: 0.89, blue: 0.93),
                skyBottom: Color(red: 0.94, green: 0.96, blue: 0.98),
                celestialColor: Color.white.opacity(0.85),
                cloudColor: Color.white.opacity(0.82),
                hillFar: Color(red: 0.82, green: 0.87, blue: 0.91),
                hillNear: Color(red: 0.89, green: 0.93, blue: 0.95),
                trunkDark: Color(red: 0.35, green: 0.30, blue: 0.28),
                trunkLight: Color(red: 0.48, green: 0.42, blue: 0.40),
                leafBack: Color(red: 0.34, green: 0.46, blue: 0.48),
                leafMid: Color(red: 0.47, green: 0.59, blue: 0.60),
                leafFront: Color(red: 0.64, green: 0.75, blue: 0.77),
                leafAccent: Color(red: 0.92, green: 0.95, blue: 0.97),
                precipitationColor: Color.white,
                plaqueBackground: Color(red: 0.99, green: 0.98, blue: 0.95),
                plaqueBorder: Color(red: 0.73, green: 0.74, blue: 0.76),
                plaqueText: Color(red: 0.20, green: 0.22, blue: 0.25),
                plaqueDate: Color(red: 0.47, green: 0.51, blue: 0.56)
            )
        case .thunderstorm:
            return TreeAtmospherePalette(
                skyTop: Color(red: 0.30, green: 0.35, blue: 0.45),
                skyMid: Color(red: 0.42, green: 0.47, blue: 0.56),
                skyBottom: Color(red: 0.59, green: 0.63, blue: 0.69),
                celestialColor: Color(red: 0.92, green: 0.95, blue: 1.0),
                cloudColor: Color(red: 0.46, green: 0.50, blue: 0.58).opacity(0.9),
                hillFar: Color(red: 0.36, green: 0.44, blue: 0.46),
                hillNear: Color(red: 0.27, green: 0.37, blue: 0.36),
                trunkDark: Color(red: 0.20, green: 0.17, blue: 0.15),
                trunkLight: Color(red: 0.30, green: 0.26, blue: 0.23),
                leafBack: Color(red: 0.16, green: 0.28, blue: 0.26),
                leafMid: Color(red: 0.22, green: 0.37, blue: 0.33),
                leafFront: Color(red: 0.30, green: 0.46, blue: 0.39),
                leafAccent: Color(red: 0.44, green: 0.58, blue: 0.51),
                precipitationColor: Color(red: 0.85, green: 0.92, blue: 1.0),
                plaqueBackground: Color(red: 0.94, green: 0.92, blue: 0.88),
                plaqueBorder: Color(red: 0.55, green: 0.53, blue: 0.50),
                plaqueText: Color(red: 0.16, green: 0.17, blue: 0.18),
                plaqueDate: Color(red: 0.40, green: 0.42, blue: 0.44)
            )
        }
    }

    private static func darkPalette(for kind: TreeWeatherKind) -> TreeAtmospherePalette {
        switch kind {
        case .clear:
            return TreeAtmospherePalette(
                skyTop: Color(red: 0.08, green: 0.11, blue: 0.17),
                skyMid: Color(red: 0.12, green: 0.16, blue: 0.22),
                skyBottom: Color(red: 0.17, green: 0.21, blue: 0.24),
                celestialColor: Color(red: 0.98, green: 0.95, blue: 0.82),
                cloudColor: Color.white.opacity(0.14),
                hillFar: Color(red: 0.13, green: 0.19, blue: 0.17),
                hillNear: Color(red: 0.10, green: 0.16, blue: 0.13),
                trunkDark: Color(red: 0.16, green: 0.13, blue: 0.11),
                trunkLight: Color(red: 0.25, green: 0.20, blue: 0.16),
                leafBack: Color(red: 0.12, green: 0.22, blue: 0.17),
                leafMid: Color(red: 0.18, green: 0.31, blue: 0.22),
                leafFront: Color(red: 0.26, green: 0.41, blue: 0.28),
                leafAccent: Color(red: 0.40, green: 0.54, blue: 0.36),
                precipitationColor: Color(red: 0.96, green: 0.92, blue: 0.72),
                plaqueBackground: Color(red: 0.20, green: 0.19, blue: 0.17),
                plaqueBorder: Color(red: 0.43, green: 0.38, blue: 0.31),
                plaqueText: Color(red: 0.94, green: 0.91, blue: 0.85),
                plaqueDate: Color(red: 0.69, green: 0.65, blue: 0.56)
            )
        case .cloudy, .fog:
            return TreeAtmospherePalette(
                skyTop: Color(red: 0.11, green: 0.13, blue: 0.16),
                skyMid: Color(red: 0.16, green: 0.19, blue: 0.21),
                skyBottom: Color(red: 0.21, green: 0.24, blue: 0.25),
                celestialColor: Color.white.opacity(0.35),
                cloudColor: Color.white.opacity(0.18),
                hillFar: Color(red: 0.15, green: 0.19, blue: 0.19),
                hillNear: Color(red: 0.12, green: 0.16, blue: 0.15),
                trunkDark: Color(red: 0.16, green: 0.14, blue: 0.13),
                trunkLight: Color(red: 0.24, green: 0.21, blue: 0.19),
                leafBack: Color(red: 0.13, green: 0.22, blue: 0.19),
                leafMid: Color(red: 0.19, green: 0.30, blue: 0.25),
                leafFront: Color(red: 0.27, green: 0.39, blue: 0.32),
                leafAccent: Color(red: 0.41, green: 0.51, blue: 0.44),
                precipitationColor: Color.white.opacity(0.24),
                plaqueBackground: Color(red: 0.19, green: 0.19, blue: 0.18),
                plaqueBorder: Color(red: 0.40, green: 0.39, blue: 0.36),
                plaqueText: Color(red: 0.92, green: 0.91, blue: 0.88),
                plaqueDate: Color(red: 0.66, green: 0.65, blue: 0.62)
            )
        case .rain, .thunderstorm:
            return TreeAtmospherePalette(
                skyTop: Color(red: 0.07, green: 0.09, blue: 0.14),
                skyMid: Color(red: 0.11, green: 0.14, blue: 0.19),
                skyBottom: Color(red: 0.16, green: 0.19, blue: 0.23),
                celestialColor: Color(red: 0.80, green: 0.88, blue: 1.0),
                cloudColor: Color(red: 0.26, green: 0.30, blue: 0.37).opacity(0.65),
                hillFar: Color(red: 0.11, green: 0.16, blue: 0.17),
                hillNear: Color(red: 0.08, green: 0.13, blue: 0.13),
                trunkDark: Color(red: 0.13, green: 0.11, blue: 0.10),
                trunkLight: Color(red: 0.20, green: 0.18, blue: 0.16),
                leafBack: Color(red: 0.09, green: 0.18, blue: 0.17),
                leafMid: Color(red: 0.14, green: 0.25, blue: 0.22),
                leafFront: Color(red: 0.20, green: 0.34, blue: 0.28),
                leafAccent: Color(red: 0.32, green: 0.47, blue: 0.40),
                precipitationColor: Color(red: 0.72, green: 0.84, blue: 0.98),
                plaqueBackground: Color(red: 0.17, green: 0.18, blue: 0.19),
                plaqueBorder: Color(red: 0.36, green: 0.39, blue: 0.42),
                plaqueText: Color(red: 0.91, green: 0.92, blue: 0.93),
                plaqueDate: Color(red: 0.62, green: 0.66, blue: 0.70)
            )
        case .snow:
            return TreeAtmospherePalette(
                skyTop: Color(red: 0.11, green: 0.15, blue: 0.21),
                skyMid: Color(red: 0.16, green: 0.21, blue: 0.27),
                skyBottom: Color(red: 0.23, green: 0.28, blue: 0.33),
                celestialColor: Color(red: 0.94, green: 0.97, blue: 1.0),
                cloudColor: Color.white.opacity(0.22),
                hillFar: Color(red: 0.22, green: 0.27, blue: 0.31),
                hillNear: Color(red: 0.28, green: 0.33, blue: 0.37),
                trunkDark: Color(red: 0.17, green: 0.15, blue: 0.15),
                trunkLight: Color(red: 0.26, green: 0.23, blue: 0.22),
                leafBack: Color(red: 0.15, green: 0.23, blue: 0.25),
                leafMid: Color(red: 0.22, green: 0.32, blue: 0.34),
                leafFront: Color(red: 0.34, green: 0.44, blue: 0.47),
                leafAccent: Color(red: 0.78, green: 0.85, blue: 0.90),
                precipitationColor: Color.white.opacity(0.9),
                plaqueBackground: Color(red: 0.19, green: 0.21, blue: 0.23),
                plaqueBorder: Color(red: 0.42, green: 0.46, blue: 0.50),
                plaqueText: Color(red: 0.94, green: 0.95, blue: 0.97),
                plaqueDate: Color(red: 0.68, green: 0.73, blue: 0.78)
            )
        }
    }
}

/// Manages on-demand weather for the tree home scene without background polling or continuous tracking.
@MainActor @Observable
final class TreeSceneWeatherController {
    private static let cacheLifetime: TimeInterval = 30 * 60

    private let locationProvider: any DiaryLocationProviding
    private let placeNameProvider: any DiaryPlaceNameProviding
    private let weatherProvider: any DiaryWeatherProviding
    private let isValidation: Bool

    private(set) var liveWeather: DiaryWeather?
    private(set) var placeName: String?
    private(set) var isLoading = false
    private(set) var statusMessage: String?
    var previewOverride: TreeWeatherKind?
    private var lastFetchedAt: Date?
    private var fetchTask: Task<Void, Never>?

    init(
        locationProvider: any DiaryLocationProviding = SystemLocationProvider(),
        placeNameProvider: any DiaryPlaceNameProviding = SystemPlaceNameProvider(),
        weatherProvider: any DiaryWeatherProviding = OpenMeteoWeatherProvider(),
        isValidation: Bool = false
    ) {
        self.locationProvider = locationProvider
        self.placeNameProvider = placeNameProvider
        self.weatherProvider = weatherProvider
        self.isValidation = isValidation
    }

    var effectiveWeatherKind: TreeWeatherKind {
        if let previewOverride { return previewOverride }
        if let liveWeather { return TreeWeatherKind.from(weatherCode: liveWeather.weatherCode) }
        return .clear
    }

    var effectiveWindSpeedKmh: Double {
        if let previewOverride { return previewOverride.defaultWindSpeedKmh }
        if let wind = liveWeather?.windSpeedKmh, wind.isFinite, wind >= 0 { return wind }
        return effectiveWeatherKind.defaultWindSpeedKmh
    }

    var pillLabel: String {
        if let previewOverride {
            return "预览 · \(previewOverride.label)"
        }
        if isLoading {
            return "正在同步天气…"
        }
        if let liveWeather {
            let temp = "\(Int(liveWeather.temperatureCelsius.rounded()))° \(liveWeather.conditionText)"
            if let placeName, !placeName.isEmpty {
                return "\(placeName) · \(temp)"
            }
            return temp
        }
        return "同步今日天气"
    }

    /// Only auto-fetches on launch if location authorization was already granted; never prompts unexpectedly.
    func refreshIfAuthorized() {
        guard !isValidation, liveWeather == nil, !isLoading else { return }
        if let lastFetchedAt, Date.now.timeIntervalSince(lastFetchedAt) < Self.cacheLifetime {
            return
        }
        let status = CLLocationManager().authorizationStatus
        guard status == .authorizedAlways else { return }
        refreshLiveWeather()
    }

    func refreshLiveWeather() {
        guard !isValidation, !isLoading else { return }
        previewOverride = nil
        fetchTask?.cancel()
        isLoading = true
        statusMessage = nil

        fetchTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isLoading = false }
            do {
                let location = try await self.locationProvider.requestCurrentLocation()
                guard !Task.isCancelled else { return }
                let weather = try await self.weatherProvider.currentWeather(for: location)
                guard !Task.isCancelled else { return }
                let place = try? await self.placeNameProvider.placeName(for: location)
                guard !Task.isCancelled else { return }
                self.liveWeather = weather
                self.placeName = place
                self.lastFetchedAt = .now
                self.statusMessage = nil
            } catch is CancellationError {
                return
            } catch let error as DiaryLocationRequestError {
                self.statusMessage = error.localizedDescription
            } catch let error as DiaryWeatherRequestError {
                self.statusMessage = error.localizedDescription
            } catch {
                self.statusMessage = "暂时无法获取天气"
            }
        }
    }
}
