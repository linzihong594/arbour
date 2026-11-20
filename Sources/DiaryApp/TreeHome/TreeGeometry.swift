import Foundation
import SwiftUI

struct PlaqueAnchor: Sendable {
    let branchPoint: CGPoint
    let cordLength: CGFloat
    let phase: Double
}

struct TreeBranch: Sendable {
    let p0: CGPoint
    let c1: CGPoint
    let c2: CGPoint
    let p3: CGPoint
    let startWidth: CGFloat
    let endWidth: CGFloat
    let tier: Int  // 0: primary limb, 1: secondary bough, 2: fine twig
    let minStage: Int
}

/// Canonical tree world (1200×860) with constant camera scale so growth genuinely raises trunk height
/// and sprouts new leafy boughs & hanging slots rather than zooming the canvas.
enum TreeGeometry {
    static let artWidth: CGFloat = 1200
    static let artHeight: CGFloat = 860
    static let artOrigin = CGPoint(x: 600, y: 790)

    struct Layout {
        let origin: CGPoint
        let scale: CGFloat
        let artRect: CGRect

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
        }

        func point(_ p: CGPoint) -> CGPoint {
            CGPoint(x: origin.x + p.x * scale, y: origin.y + p.y * scale)
        }
    }

    /// Constant world-to-viewport scale so the meadow and plaques stay consistent while the tree itself grows taller.
    static func layout(for size: CGSize, stage _: TreeGrowthStage) -> Layout {
        let scale = max(0.64, min(1.48, min(size.width / 1080, size.height / 740)))
        let origin = CGPoint(x: size.width * 0.50, y: size.height * 0.91)
        let width = artWidth * scale
        let height = artHeight * scale
        let artRect = CGRect(
            x: origin.x - artOrigin.x * scale,
            y: origin.y - artOrigin.y * scale,
            width: width,
            height: height
        )
        return Layout(origin: origin, scale: scale, artRect: artRect)
    }

    // MARK: - Stage-by-Stage Organic Branching (Every Higher Stage Sprouts Real New Leafy Boughs)

    static let branches: [TreeBranch] = [
        // --- Stage 0 (幼苗): 3 tender shoots sprouting from the short sapling stem (-178) ---
        TreeBranch(
            p0: CGPoint(x: -5, y: -135), c1: CGPoint(x: -56, y: -158),
            c2: CGPoint(x: -115, y: -182), p3: CGPoint(x: -168, y: -215),
            startWidth: 16, endWidth: 4.5, tier: 0, minStage: 0),
        TreeBranch(
            p0: CGPoint(x: 0, y: -168), c1: CGPoint(x: 8, y: -212),
            c2: CGPoint(x: 24, y: -252), p3: CGPoint(x: 44, y: -286),
            startWidth: 13, endWidth: 4.0, tier: 0, minStage: 0),
        TreeBranch(
            p0: CGPoint(x: 6, y: -142), c1: CGPoint(x: 60, y: -164),
            c2: CGPoint(x: 118, y: -185), p3: CGPoint(x: 175, y: -210),
            startWidth: 15.5, endWidth: 4.5, tier: 0, minStage: 0),

        // --- Stage 1 (小树): taller trunk (-260) sprouts wider lower & mid boughs ---
        TreeBranch(
            p0: CGPoint(x: -14, y: -158), c1: CGPoint(x: -102, y: -172),
            c2: CGPoint(x: -202, y: -184), p3: CGPoint(x: -292, y: -196),
            startWidth: 22, endWidth: 6.0, tier: 0, minStage: 1),
        TreeBranch(
            p0: CGPoint(x: 15, y: -164), c1: CGPoint(x: 105, y: -176),
            c2: CGPoint(x: 205, y: -186), p3: CGPoint(x: 298, y: -192),
            startWidth: 22, endWidth: 6.0, tier: 0, minStage: 1),
        TreeBranch(
            p0: CGPoint(x: -10, y: -236), c1: CGPoint(x: -88, y: -288),
            c2: CGPoint(x: -175, y: -332), p3: CGPoint(x: -265, y: -368),
            startWidth: 19, endWidth: 5.5, tier: 0, minStage: 1),
        TreeBranch(
            p0: CGPoint(x: 10, y: -242), c1: CGPoint(x: 92, y: -292),
            c2: CGPoint(x: 182, y: -336), p3: CGPoint(x: 272, y: -366),
            startWidth: 19, endWidth: 5.5, tier: 0, minStage: 1),
        TreeBranch(
            p0: CGPoint(x: -6, y: -212), c1: CGPoint(x: 22, y: -222),
            c2: CGPoint(x: 54, y: -226), p3: CGPoint(x: 88, y: -220),
            startWidth: 9.5, endWidth: 3.5, tier: 1, minStage: 1),

        // --- Stage 2 (繁茂大树): trunk reaches -332, sprouts sweeping secondary boughs & upper fork ---
        TreeBranch(
            p0: CGPoint(x: -155, y: -178), c1: CGPoint(x: -225, y: -154),
            c2: CGPoint(x: -300, y: -148), p3: CGPoint(x: -378, y: -162),
            startWidth: 13.5, endWidth: 4.2, tier: 1, minStage: 2),
        TreeBranch(
            p0: CGPoint(x: 162, y: -180), c1: CGPoint(x: 230, y: -156),
            c2: CGPoint(x: 306, y: -150), p3: CGPoint(x: 386, y: -162),
            startWidth: 13.5, endWidth: 4.2, tier: 1, minStage: 2),
        TreeBranch(
            p0: CGPoint(x: -220, y: -188), c1: CGPoint(x: -288, y: -232),
            c2: CGPoint(x: -358, y: -268), p3: CGPoint(x: -430, y: -286),
            startWidth: 12.5, endWidth: 3.8, tier: 1, minStage: 2),
        TreeBranch(
            p0: CGPoint(x: 226, y: -188), c1: CGPoint(x: 294, y: -230),
            c2: CGPoint(x: 365, y: -264), p3: CGPoint(x: 438, y: -280),
            startWidth: 12.5, endWidth: 3.8, tier: 1, minStage: 2),
        TreeBranch(
            p0: CGPoint(x: -8, y: -312), c1: CGPoint(x: -64, y: -390),
            c2: CGPoint(x: -132, y: -454), p3: CGPoint(x: -206, y: -502),
            startWidth: 17.5, endWidth: 5.0, tier: 0, minStage: 2),
        TreeBranch(
            p0: CGPoint(x: 8, y: -318), c1: CGPoint(x: 68, y: -396),
            c2: CGPoint(x: 140, y: -458), p3: CGPoint(x: 215, y: -502),
            startWidth: 17.5, endWidth: 5.0, tier: 0, minStage: 2),
        TreeBranch(
            p0: CGPoint(x: -165, y: -322), c1: CGPoint(x: -235, y: -386),
            c2: CGPoint(x: -302, y: -435), p3: CGPoint(x: -368, y: -468),
            startWidth: 11.5, endWidth: 3.5, tier: 1, minStage: 2),
        TreeBranch(
            p0: CGPoint(x: 170, y: -324), c1: CGPoint(x: 242, y: -386),
            c2: CGPoint(x: 312, y: -434), p3: CGPoint(x: 378, y: -464),
            startWidth: 11.5, endWidth: 3.5, tier: 1, minStage: 2),

        // --- Stage 3 (参天古树): trunk rises to -392, sprouts high soaring crown limbs & fine twigs ---
        TreeBranch(
            p0: CGPoint(x: -6, y: -378), c1: CGPoint(x: -44, y: -468),
            c2: CGPoint(x: -92, y: -545), p3: CGPoint(x: -148, y: -608),
            startWidth: 14.5, endWidth: 4.2, tier: 0, minStage: 3),
        TreeBranch(
            p0: CGPoint(x: 6, y: -382), c1: CGPoint(x: 42, y: -474),
            c2: CGPoint(x: 88, y: -552), p3: CGPoint(x: 144, y: -616),
            startWidth: 14.5, endWidth: 4.2, tier: 0, minStage: 3),
        TreeBranch(
            p0: CGPoint(x: -292, y: -196), c1: CGPoint(x: -365, y: -214),
            c2: CGPoint(x: -435, y: -222), p3: CGPoint(x: -498, y: -216),
            startWidth: 9.5, endWidth: 2.8, tier: 1, minStage: 3),
        TreeBranch(
            p0: CGPoint(x: 298, y: -192), c1: CGPoint(x: 372, y: -210),
            c2: CGPoint(x: 440, y: -216), p3: CGPoint(x: 504, y: -210),
            startWidth: 9.5, endWidth: 2.8, tier: 1, minStage: 3),
        TreeBranch(
            p0: CGPoint(x: -265, y: -368), c1: CGPoint(x: -338, y: -386),
            c2: CGPoint(x: -408, y: -388), p3: CGPoint(x: -468, y: -376),
            startWidth: 8.5, endWidth: 2.4, tier: 2, minStage: 3),
        TreeBranch(
            p0: CGPoint(x: 272, y: -366), c1: CGPoint(x: 345, y: -384),
            c2: CGPoint(x: 414, y: -384), p3: CGPoint(x: 474, y: -372),
            startWidth: 8.5, endWidth: 2.4, tier: 2, minStage: 3),

        // --- Stage 4 (记忆巨木): towering trunk (-445) & sky-high spreading crown boughs ---
        TreeBranch(
            p0: CGPoint(x: -4, y: -435), c1: CGPoint(x: -18, y: -528),
            c2: CGPoint(x: -28, y: -612), p3: CGPoint(x: -22, y: -688),
            startWidth: 12.0, endWidth: 3.4, tier: 0, minStage: 4),
        TreeBranch(
            p0: CGPoint(x: 4, y: -438), c1: CGPoint(x: 48, y: -525),
            c2: CGPoint(x: 98, y: -604), p3: CGPoint(x: 158, y: -668),
            startWidth: 11.5, endWidth: 3.2, tier: 1, minStage: 4),
        TreeBranch(
            p0: CGPoint(x: -148, y: -608), c1: CGPoint(x: -216, y: -632),
            c2: CGPoint(x: -280, y: -635), p3: CGPoint(x: -338, y: -616),
            startWidth: 7.5, endWidth: 2.2, tier: 2, minStage: 4),
        TreeBranch(
            p0: CGPoint(x: 144, y: -616), c1: CGPoint(x: 214, y: -638),
            c2: CGPoint(x: 278, y: -638), p3: CGPoint(x: 336, y: -618),
            startWidth: 7.5, endWidth: 2.2, tier: 2, minStage: 4),
        TreeBranch(
            p0: CGPoint(x: -378, y: -162), c1: CGPoint(x: -432, y: -144),
            c2: CGPoint(x: -485, y: -142), p3: CGPoint(x: -535, y: -158),
            startWidth: 7.0, endWidth: 2.2, tier: 2, minStage: 4),
        TreeBranch(
            p0: CGPoint(x: 386, y: -162), c1: CGPoint(x: 440, y: -144),
            c2: CGPoint(x: 492, y: -142), p3: CGPoint(x: 540, y: -158),
            startWidth: 7.0, endWidth: 2.2, tier: 2, minStage: 4),
    ]

    static func cubicPoint(_ b: TreeBranch, t: CGFloat) -> CGPoint {
        let u = 1 - t
        let tt = t * t
        let uu = u * u
        let uuu = uu * u
        let ttt = tt * t
        let x = uuu * b.p0.x + 3 * uu * t * b.c1.x + 3 * u * tt * b.c2.x + ttt * b.p3.x
        let y = uuu * b.p0.y + 3 * uu * t * b.c1.y + 3 * u * tt * b.c2.y + ttt * b.p3.y
        return CGPoint(x: x, y: y)
    }

    private struct BranchAnchorSpec {
        let branchIndex: Int
        let t: CGFloat
        let cord: CGFloat
        let phase: Double
    }

    // 22 plaque anchor points ordered by stage so new branches naturally unlock new hanging spots!
    private static let anchorSpecs: [BranchAnchorSpec] = [
        // Stage 0 sapling slots (3)
        BranchAnchorSpec(branchIndex: 0, t: 0.62, cord: 22, phase: 0.4),
        BranchAnchorSpec(branchIndex: 1, t: 0.55, cord: 20, phase: 1.7),
        BranchAnchorSpec(branchIndex: 2, t: 0.62, cord: 22, phase: 2.8),
        // Stage 1 young tree slots (+5 = 8): upper boughs first so plaques spread cleanly even at 820x580
        BranchAnchorSpec(branchIndex: 5, t: 0.58, cord: 22, phase: 0.9),
        BranchAnchorSpec(branchIndex: 6, t: 0.58, cord: 22, phase: 4.0),
        BranchAnchorSpec(branchIndex: 3, t: 0.86, cord: 24, phase: 1.1),
        BranchAnchorSpec(branchIndex: 4, t: 0.86, cord: 24, phase: 3.4),
        BranchAnchorSpec(branchIndex: 7, t: 0.65, cord: 20, phase: 2.1),
        // Stage 2 lush tree slots (+6 = 14)
        BranchAnchorSpec(branchIndex: 8, t: 0.55, cord: 24, phase: 1.5),
        BranchAnchorSpec(branchIndex: 9, t: 0.55, cord: 24, phase: 2.6),
        BranchAnchorSpec(branchIndex: 10, t: 0.66, cord: 24, phase: 3.9),
        BranchAnchorSpec(branchIndex: 11, t: 0.66, cord: 24, phase: 0.6),
        BranchAnchorSpec(branchIndex: 12, t: 0.56, cord: 22, phase: 2.3),
        BranchAnchorSpec(branchIndex: 13, t: 0.56, cord: 22, phase: 1.2),
        // Stage 3 ancient tree slots (+4 = 18)
        BranchAnchorSpec(branchIndex: 18, t: 0.58, cord: 22, phase: 3.1),
        BranchAnchorSpec(branchIndex: 19, t: 0.58, cord: 22, phase: 4.5),
        BranchAnchorSpec(branchIndex: 14, t: 0.62, cord: 22, phase: 0.8),
        BranchAnchorSpec(branchIndex: 15, t: 0.62, cord: 22, phase: 2.0),
        // Stage 4 giant tree slots (+4 = 22)
        BranchAnchorSpec(branchIndex: 16, t: 0.58, cord: 22, phase: 1.4),
        BranchAnchorSpec(branchIndex: 17, t: 0.58, cord: 22, phase: 3.6),
        BranchAnchorSpec(branchIndex: 26, t: 0.55, cord: 22, phase: 2.7),
        BranchAnchorSpec(branchIndex: 27, t: 0.55, cord: 22, phase: 0.3),
    ]

    /// Returns only the anchors that belong to currently grown branches of `stage`.
    static func plaqueAnchors(in size: CGSize, stage: TreeGrowthStage) -> [PlaqueAnchor] {
        let layout = layout(for: size, stage: stage)
        let activeSpecs = anchorSpecs.filter { branches[$0.branchIndex].minStage <= stage.rawValue }
        return activeSpecs.map { spec in
            let normalized = cubicPoint(branches[spec.branchIndex], t: spec.t)
            return PlaqueAnchor(
                branchPoint: layout.point(normalized),
                cordLength: spec.cord * layout.scale,
                phase: spec.phase
            )
        }
    }

    /// Natural pendulum sway angle in degrees, synchronized with canopy wind & gusts.
    static func plaqueSwayDegrees(time: Double, windSpeedKmh: Double, phase: Double) -> Double {
        let strength = min(2.2, max(0.5, windSpeedKmh / 12.0))
        let gust = 1.0 + 0.30 * sin(time * 0.42) + 0.16 * sin(time * 1.07)
        let primary = sin(time * (1.28 + strength * 0.32) + phase)
        let harmonic = 0.28 * sin(time * 2.15 + phase * 1.6)
        return (primary + harmonic) * (1.8 * strength * gust)
    }
}
