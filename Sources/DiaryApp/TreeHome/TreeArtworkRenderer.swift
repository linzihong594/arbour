import AppKit
import CoreGraphics
import Foundation
import SwiftUI

struct TreeArtworkKey: Equatable, Hashable {
    let weatherKind: TreeWeatherKind
    let season: TreeSeason
    let isDark: Bool
    let stage: TreeGrowthStage
}

struct TreeArtworkSet {
    let key: TreeArtworkKey
    let backCanopy: CGImage
    let trunkAndBranches: CGImage
    let midCanopy: CGImage
    let frontCanopy: CGImage
}

/// Offscreen 8-bit sRGB botanical painter: renders 1,200+ crisp pointed leaves and gnarled bark once per
/// (weather, appearance, growthStage) so runtime wind animation only composites 4 lightweight GPU textures.
@MainActor
final class TreeArtworkCache {
    static let shared = TreeArtworkCache()
    private var current: TreeArtworkSet?

    func artwork(for key: TreeArtworkKey, palette: TreeAtmospherePalette) -> TreeArtworkSet {
        if let current, current.key == key {
            return current
        }
        let generated = TreeArtworkRenderer.render(key: key, palette: palette)
        current = generated
        return generated
    }
}

private enum TreeArtworkRenderer {
    // Render at 0.8x (960x688) of canonical 1200x860 space: ~36% less GPU/RAM with crisp organic foliage.
    private static let renderScale: CGFloat = 0.80
    private static let width = Int(TreeGeometry.artWidth * renderScale)
    private static let height = Int(TreeGeometry.artHeight * renderScale)
    private static let origin = TreeGeometry.artOrigin

    static func render(key: TreeArtworkKey, palette: TreeAtmospherePalette) -> TreeArtworkSet {
        let leafBack = cgColor(palette.leafBack)
        let leafMid = cgColor(palette.leafMid)
        let leafFront = cgColor(palette.leafFront)
        let leafAccent = cgColor(palette.leafAccent)
        let trunkDark = cgColor(palette.trunkDark)
        let trunkLight = cgColor(palette.trunkLight)

        let back = makeLayer { ctx in
            drawFoliageLayer(
                in: ctx, stage: key.stage, layer: .back,
                primary: leafBack, secondary: darkened(leafBack, factor: 0.80),
                isDark: key.isDark)
        }

        let trunk = makeLayer { ctx in
            drawTrunkRootsAndBranches(
                in: ctx, stage: key.stage,
                trunkDark: trunkDark, trunkLight: trunkLight, isDark: key.isDark)
        }

        let mid = makeLayer { ctx in
            drawFoliageLayer(
                in: ctx, stage: key.stage, layer: .mid,
                primary: leafMid, secondary: leafBack,
                isDark: key.isDark)
        }

        let front = makeLayer { ctx in
            drawFoliageLayer(
                in: ctx, stage: key.stage, layer: .front,
                primary: leafFront, secondary: leafAccent,
                isDark: key.isDark)
        }

        return TreeArtworkSet(
            key: key,
            backCanopy: back,
            trunkAndBranches: trunk,
            midCanopy: mid,
            frontCanopy: front
        )
    }

    // MARK: - 8-bit sRGB Bitmap Context (Half the RAM of 16-bit Linear Metal Canvases)

    private static func makeLayer(_ draw: (CGContext) -> Void) -> CGImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard
            let ctx = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            )
        else {
            fatalError("Unable to allocate offscreen bitmap for tree artwork")
        }
        // Flip to top-left origin and scale from canonical 1200×860 space into compact 960×688 bitmap.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: renderScale, y: -renderScale)
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        draw(ctx)
        return ctx.makeImage()!
    }

    private static func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: origin.x + x, y: origin.y + y)
    }

    private static func pt(_ p: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + p.x, y: origin.y + p.y)
    }

    private static func hash(_ seed: Int) -> Double {
        let x = sin(Double(seed) * 12.9898 + 78.233) * 43758.5453
        return x - floor(x)
    }

    // MARK: - Graceful Organic Trunk, Rounded Roots, Bark Grain & Seamless Forking Limbs

    private static func drawTrunkRootsAndBranches(
        in ctx: CGContext,
        stage: TreeGrowthStage,
        trunkDark: CGColor,
        trunkLight: CGColor,
        isDark: Bool
    ) {
        let ts = stage.trunkScale
        let topY = stage.trunkTopY
        let midY = topY * 0.54
        let lowerY = topY * 0.16
        let shadowBark = darkened(trunkDark, factor: 0.78)

        // 1. Graceful S-curved trunk whose actual height grows from -178 (sapling) to -445 (giant).
        let trunk = CGMutablePath()
        trunk.move(to: pt(-78 * ts, 16))
        trunk.addCurve(
            to: pt(-35 * ts, lowerY),
            control1: pt(-52 * ts, 8),
            control2: pt(-41 * ts, lowerY * 0.35))
        trunk.addCurve(
            to: pt(-22 * ts, midY),
            control1: pt(-30 * ts, lowerY + (midY - lowerY) * 0.40),
            control2: pt(-27 * ts, lowerY + (midY - lowerY) * 0.72))
        trunk.addCurve(
            to: pt(-9 * ts, topY),
            control1: pt(-17 * ts, midY + (topY - midY) * 0.38),
            control2: pt(-13 * ts, midY + (topY - midY) * 0.72))
        trunk.addQuadCurve(to: pt(9 * ts, topY - 4), control: pt(0, topY - 14))
        trunk.addCurve(
            to: pt(23 * ts, midY),
            control1: pt(14 * ts, midY + (topY - midY) * 0.72),
            control2: pt(18 * ts, midY + (topY - midY) * 0.38))
        trunk.addCurve(
            to: pt(37 * ts, lowerY),
            control1: pt(29 * ts, lowerY + (midY - lowerY) * 0.72),
            control2: pt(32 * ts, lowerY + (midY - lowerY) * 0.40))
        trunk.addCurve(
            to: pt(82 * ts, 16),
            control1: pt(43 * ts, lowerY * 0.35),
            control2: pt(56 * ts, 8))
        trunk.addCurve(
            to: pt(0, 19),
            control1: pt(50 * ts, 22),
            control2: pt(22 * ts, 21))
        trunk.addCurve(
            to: pt(-78 * ts, 16),
            control1: pt(-22 * ts, 21),
            control2: pt(-50 * ts, 22))
        trunk.closeSubpath()

        // 2. Draw soft rounded roots and main trunk first with warm directional bark gradient.
        let activeBranches = TreeGeometry.branches.filter { $0.minStage <= stage.rawValue }
        let rootSpecs: [(CGPoint, CGPoint, CGPoint, CGFloat, CGFloat)] = [
            (
                CGPoint(x: -40 * ts, y: -10), CGPoint(x: -70 * ts, y: 10),
                CGPoint(x: -104 * ts, y: 17), 15 * ts, 4.5 * ts
            ),
            (
                CGPoint(x: -18 * ts, y: 2), CGPoint(x: -30 * ts, y: 14),
                CGPoint(x: -46 * ts, y: 22), 11 * ts, 3.5 * ts
            ),
            (
                CGPoint(x: 18 * ts, y: 2), CGPoint(x: 32 * ts, y: 14),
                CGPoint(x: 48 * ts, y: 22), 11 * ts, 3.5 * ts
            ),
            (
                CGPoint(x: 42 * ts, y: -10), CGPoint(x: 74 * ts, y: 9),
                CGPoint(x: 108 * ts, y: 16), 15 * ts, 4.5 * ts
            ),
        ]

        let woodColors = [shadowBark, trunkDark, trunkLight, trunkDark] as CFArray
        let woodLocs: [CGFloat] = [0.0, 0.36, 0.78, 1.0]
        let woodGradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: woodColors, locations: woodLocs)

        func fillWithWoodGradient(_ path: CGPath) {
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            if let woodGradient {
                ctx.drawLinearGradient(
                    woodGradient,
                    start: pt(-180 * ts, -220),
                    end: pt(220 * ts, -220),
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            }
            ctx.restoreGState()
        }

        for (p0, ctrl, p1, w0, w1) in rootSpecs {
            fillWithWoodGradient(
                taperedQuadraticPolygon(
                    p0: pt(p0), ctrl: pt(ctrl), p1: pt(p1), startWidth: w0, endWidth: w1))
        }
        fillWithWoodGradient(trunk)

        for b in activeBranches {
            let anchoredBranch: TreeBranch
            if b.tier == 0 {
                let insetX: CGFloat = b.p0.x < 0 ? min(0, b.p0.x + 12 * ts) : max(0, b.p0.x - 12 * ts)
                anchoredBranch = TreeBranch(
                    p0: CGPoint(x: insetX, y: b.p0.y + 12),
                    c1: b.c1, c2: b.c2, p3: b.p3,
                    startWidth: b.startWidth * ts * 0.92,
                    endWidth: max(1.6, b.endWidth * ts),
                    tier: b.tier, minStage: b.minStage)
            } else {
                anchoredBranch = TreeBranch(
                    p0: b.p0, c1: b.c1, c2: b.c2, p3: b.p3,
                    startWidth: b.startWidth * ts,
                    endWidth: max(1.5, b.endWidth * ts),
                    tier: b.tier, minStage: b.minStage)
            }
            fillWithWoodGradient(
                taperedCubicPolygon(
                    branch: anchoredBranch,
                    startWidth: anchoredBranch.startWidth,
                    endWidth: anchoredBranch.endWidth,
                    steps: 14))
        }

        // Delicate organic bark flow lines scaled cleanly to the trunk's real height.
        ctx.setLineCap(.round)
        let barkLines: [(CGPoint, CGPoint, CGPoint, Bool)] = [
            (
                CGPoint(x: -20 * ts, y: -12), CGPoint(x: -16 * ts, y: topY * 0.35),
                CGPoint(x: -10 * ts, y: topY * 0.72), false
            ),
            (
                CGPoint(x: -8 * ts, y: -4), CGPoint(x: -6 * ts, y: topY * 0.42),
                CGPoint(x: -4 * ts, y: topY * 0.86), false
            ),
            (
                CGPoint(x: 4 * ts, y: -14), CGPoint(x: 6 * ts, y: topY * 0.38),
                CGPoint(x: 4 * ts, y: topY * 0.78), true
            ),
            (
                CGPoint(x: 15 * ts, y: -8), CGPoint(x: 17 * ts, y: topY * 0.32),
                CGPoint(x: 12 * ts, y: topY * 0.62), true
            ),
            (
                CGPoint(x: 24 * ts, y: -16), CGPoint(x: 22 * ts, y: topY * 0.24),
                CGPoint(x: 16 * ts, y: topY * 0.45), false
            ),
        ]
        for (p0, ctrl, p1, isHighlight) in barkLines {
            ctx.beginPath()
            ctx.move(to: pt(p0))
            ctx.addQuadCurve(to: pt(p1), control: pt(ctrl))
            ctx.setStrokeColor(
                isHighlight
                    ? trunkLight.copy(alpha: 0.36) ?? trunkLight
                    : CGColor(gray: 0, alpha: isDark ? 0.30 : 0.16))
            ctx.setLineWidth(max(1.1, 1.8 * ts))
            ctx.strokePath()
        }

        // Warm sunlit rim along upper edge of major limbs + organic sprouting fine twigs.
        for (idx, b) in activeBranches.enumerated() {
            if b.tier < 2 {
                ctx.beginPath()
                ctx.move(to: pt(b.p0))
                ctx.addCurve(to: pt(b.p3), control1: pt(b.c1), control2: pt(b.c2))
                ctx.setStrokeColor(trunkLight.copy(alpha: 0.24) ?? trunkLight)
                ctx.setLineWidth(max(1.0, b.endWidth * 0.32 * ts))
                ctx.strokePath()
            }
            if stage.rawValue >= 1 {
                drawSubTwigs(in: ctx, branch: b, seedBase: idx * 31 + 17, trunkDark: trunkDark, ts: ts)
            }
        }
    }

    private static func drawSubTwigs(
        in ctx: CGContext,
        branch b: TreeBranch,
        seedBase: Int,
        trunkDark: CGColor,
        ts: CGFloat
    ) {
        let twigCount = b.tier == 0 ? 3 : 2
        ctx.setStrokeColor(darkened(trunkDark, factor: 0.90))
        ctx.setLineCap(.round)

        for i in 0..<twigCount {
            let t = CGFloat(0.55 + Double(i) * 0.18)
            let start = TreeGeometry.cubicPoint(b, t: min(0.95, t))
            let ahead = TreeGeometry.cubicPoint(b, t: min(1.0, t + 0.04))
            let baseAngle = atan2(ahead.y - start.y, ahead.x - start.x)
            let side: Double = i.isMultiple(of: 2) ? 1.0 : -1.0
            let angle = baseAngle + side * (0.42 + hash(seedBase + i * 7) * 0.35)
            let len = CGFloat(28 + hash(seedBase + i * 11) * 32)
            let end = CGPoint(
                x: start.x + CGFloat(cos(angle)) * len,
                y: start.y + CGFloat(sin(angle)) * len)
            let ctrl = CGPoint(
                x: (start.x + end.x) * 0.5 + CGFloat(cos(angle + 0.4)) * 8,
                y: (start.y + end.y) * 0.5 + CGFloat(sin(angle + 0.4)) * 8)

            ctx.beginPath()
            ctx.move(to: pt(start))
            ctx.addQuadCurve(to: pt(end), control: pt(ctrl))
            ctx.setLineWidth(max(1.2, (3.2 - CGFloat(b.tier)) * ts))
            ctx.strokePath()
        }
    }

    // MARK: - Painterly Botanical Foliage (1,200+ Pointed Leaves, Zero Geometric Round Blobs)

    private enum FoliageDepth {
        case back, mid, front
    }

    private static func drawFoliageLayer(
        in ctx: CGContext,
        stage: TreeGrowthStage,
        layer: FoliageDepth,
        primary: CGColor,
        secondary: CGColor,
        isDark: Bool
    ) {
        let activeBranches = TreeGeometry.branches.filter { $0.minStage <= stage.rawValue }
        let density = stage.leafDensity

        // Gather organic crown cluster centers right around the outer portions of real branches.
        var sprayCenters: [(CGPoint, CGFloat, Int, Bool)] = []
        sprayCenters.reserveCapacity(140)

        for (bIdx, b) in activeBranches.enumerated() {
            // Skip the inner bare trunk section so lower boughs remain clean for hanging plaques.
            let tStart: CGFloat = (b.tier == 0 && (bIdx == 0 || bIdx == 5)) ? 0.62 : 0.48
            let sampleCount = b.tier == 0 ? 5 : (b.tier == 1 ? 4 : 3)
            for s in 0..<sampleCount {
                let frac = sampleCount > 1 ? CGFloat(s) / CGFloat(sampleCount - 1) : 1.0
                let t = tStart + frac * (1.0 - tStart)
                let base = TreeGeometry.cubicPoint(b, t: t)
                let seed = bIdx * 100 + s * 17 + (layer == .back ? 3 : (layer == .mid ? 41 : 83))
                let jitterX = CGFloat((hash(seed) - 0.5) * 68)
                let jitterY = CGFloat((hash(seed + 1) - 0.5) * 52) - 18
                let center = CGPoint(x: base.x + jitterX, y: base.y + jitterY)
                let radius = CGFloat(42 + hash(seed + 2) * 34) * (b.tier == 2 ? 0.85 : 1.05)
                let isSunlitSide = center.y < -390 || center.x > 60
                sprayCenters.append((center, radius, seed, isSunlitSide))
            }
        }

        // Stage-gated crown dome sprays so saplings stay compact while ancient/giant trees soar high.
        var crownPoints: [(CGFloat, CGFloat, CGFloat)] = []
        if stage.rawValue >= 2 {
            crownPoints.append(contentsOf: [
                (-230, -475, 58), (-95, -515, 64), (95, -515, 64), (235, -475, 58),
            ])
        }
        if stage.rawValue >= 3 {
            crownPoints.append(contentsOf: [
                (-165, -600, 68), (0, -630, 72), (165, -605, 68),
                (-355, -425, 58), (360, -425, 58),
            ])
        }
        if stage.rawValue >= 4 {
            crownPoints.append(contentsOf: [
                (-260, -640, 66), (-35, -700, 76), (130, -685, 72), (270, -638, 66),
            ])
        }
        for (idx, cp) in crownPoints.enumerated() {
            let seed = 900 + idx * 29 + (layer == .back ? 5 : (layer == .mid ? 53 : 97))
            let isSunlit = cp.1 < -480 || cp.0 > 40
            sprayCenters.append((CGPoint(x: cp.0, y: cp.1), cp.2, seed, isSunlit))
        }

        let leavesPerSpray: Int
        switch layer {
        case .back: leavesPerSpray = max(6, Int(Double(12) * density))
        case .mid: leavesPerSpray = max(8, Int(Double(16) * density))
        case .front: leavesPerSpray = max(5, Int(Double(11) * density))
        }

        // Paint soft watercolor under-wash first on back/mid layers for lush volume without round edges.
        if layer != .front {
            for (center, radius, seed, _) in sprayCenters {
                let washColor = (layer == .back ? secondary : primary)
                    .copy(alpha: layer == .back ? 0.34 : 0.24)
                if let washColor {
                    ctx.setFillColor(washColor)
                    for k in 0..<3 {
                        let ang = hash(seed + k * 5) * .pi * 2
                        let dist = CGFloat(hash(seed + k * 7) * 0.45) * radius
                        let lx = center.x + CGFloat(cos(ang)) * dist
                        let ly = center.y + CGFloat(sin(ang)) * dist
                        drawLeafBlade(
                            in: ctx,
                            center: pt(lx, ly),
                            length: radius * 0.95,
                            width: radius * 0.56,
                            angle: hash(seed + k * 11) * .pi)
                    }
                }
            }
        }

        // Paint individual crisp pointed botanical leaf blades in organic sprays.
        for (center, radius, seed, isSunlit) in sprayCenters {
            if layer == .front && !isSunlit && hash(seed + 19) > 0.55 {
                continue
            }
            for i in 0..<leavesPerSpray {
                let s = seed * 13 + i * 7
                let theta = hash(s) * .pi * 2
                let r = sqrt(hash(s + 1)) * Double(radius)
                let lx = center.x + CGFloat(cos(theta) * r)
                let ly = center.y + CGFloat(sin(theta) * r * 0.82)

                // Point leaves naturally outward from the spray center with organic flutter variation.
                let leafAngle = theta + (hash(s + 2) - 0.5) * 1.1
                let leafLen = CGFloat(13 + hash(s + 3) * 14) * (layer == .back ? 1.15 : 0.95)
                let leafWid = leafLen * CGFloat(0.42 + hash(s + 4) * 0.16)

                let pickSecondary =
                    (layer == .front && isSunlit && hash(s + 5) > 0.42)
                    || (layer != .front && hash(s + 5) > 0.65)
                let baseColor = pickSecondary ? secondary : primary
                let alpha: CGFloat
                switch layer {
                case .back: alpha = CGFloat(0.76 + hash(s + 6) * 0.20)
                case .mid: alpha = CGFloat(0.78 + hash(s + 6) * 0.18)
                case .front: alpha = CGFloat(0.68 + hash(s + 6) * 0.26)
                }

                ctx.setFillColor(baseColor.copy(alpha: isDark ? alpha * 0.94 : alpha) ?? baseColor)
                drawLeafBlade(
                    in: ctx,
                    center: pt(lx, ly),
                    length: leafLen,
                    width: leafWid,
                    angle: leafAngle)
            }
        }
    }

    /// Draws a single tapered botanical leaf blade (pointed tip & stem) rotated around `center`.
    private static func drawLeafBlade(
        in ctx: CGContext,
        center: CGPoint,
        length: CGFloat,
        width: CGFloat,
        angle: Double
    ) {
        let halfL = length * 0.5
        let halfW = width * 0.5
        let c = CGFloat(cos(angle))
        let s = CGFloat(sin(angle))

        func xf(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: center.x + x * c - y * s, y: center.y + x * s + y * c)
        }

        ctx.beginPath()
        ctx.move(to: xf(-halfL, 0))
        ctx.addQuadCurve(to: xf(halfL, 0), control: xf(-halfL * 0.1, -halfW))
        ctx.addQuadCurve(to: xf(-halfL, 0), control: xf(-halfL * 0.1, halfW))
        ctx.closePath()
        ctx.fillPath()
    }

    // MARK: - Seamless Tapered Branch Polygons

    private static func taperedCubicPolygon(
        branch b: TreeBranch,
        startWidth: CGFloat,
        endWidth: CGFloat,
        steps: Int
    ) -> CGPath {
        var leftSide: [CGPoint] = []
        var rightSide: [CGPoint] = []
        leftSide.reserveCapacity(steps + 1)
        rightSide.reserveCapacity(steps + 1)

        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let p = pt(TreeGeometry.cubicPoint(b, t: t))
            let pPrev = pt(TreeGeometry.cubicPoint(b, t: max(0, t - 0.01)))
            let pNext = pt(TreeGeometry.cubicPoint(b, t: min(1, t + 0.01)))
            let dx = pNext.x - pPrev.x
            let dy = pNext.y - pPrev.y
            let len = max(0.001, hypot(dx, dy))
            let nx = -dy / len
            let ny = dx / len
            let halfW = (startWidth + (endWidth - startWidth) * pow(t, 0.85)) * 0.5
            leftSide.append(CGPoint(x: p.x + nx * halfW, y: p.y + ny * halfW))
            rightSide.append(CGPoint(x: p.x - nx * halfW, y: p.y - ny * halfW))
        }

        let path = CGMutablePath()
        if let first = leftSide.first {
            path.move(to: first)
            for p in leftSide.dropFirst() { path.addLine(to: p) }
            for p in rightSide.reversed() { path.addLine(to: p) }
            path.closeSubpath()
        }
        return path
    }

    private static func taperedQuadraticPolygon(
        p0: CGPoint, ctrl: CGPoint, p1: CGPoint, startWidth: CGFloat, endWidth: CGFloat
    ) -> CGPath {
        let steps = 8
        var leftSide: [CGPoint] = []
        var rightSide: [CGPoint] = []
        func quad(_ t: CGFloat) -> CGPoint {
            let u = 1 - t
            return CGPoint(
                x: u * u * p0.x + 2 * u * t * ctrl.x + t * t * p1.x,
                y: u * u * p0.y + 2 * u * t * ctrl.y + t * t * p1.y)
        }
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let p = quad(t)
            let pPrev = quad(max(0, t - 0.02))
            let pNext = quad(min(1, t + 0.02))
            let dx = pNext.x - pPrev.x
            let dy = pNext.y - pPrev.y
            let len = max(0.001, hypot(dx, dy))
            let nx = -dy / len
            let ny = dx / len
            let halfW = (startWidth + (endWidth - startWidth) * t) * 0.5
            leftSide.append(CGPoint(x: p.x + nx * halfW, y: p.y + ny * halfW))
            rightSide.append(CGPoint(x: p.x - nx * halfW, y: p.y - ny * halfW))
        }
        let path = CGMutablePath()
        if let first = leftSide.first {
            path.move(to: first)
            for p in leftSide.dropFirst() { path.addLine(to: p) }
            for p in rightSide.reversed() { path.addLine(to: p) }
            path.closeSubpath()
        }
        return path
    }

    // MARK: - Color Helpers

    private static func cgColor(_ color: Color) -> CGColor {
        NSColor(color).usingColorSpace(.sRGB)?.cgColor ?? NSColor.labelColor.cgColor
    }

    private static func darkened(_ color: CGColor, factor: CGFloat) -> CGColor {
        guard let comps = color.components, comps.count >= 3 else { return color }
        return CGColor(
            srgbRed: comps[0] * factor,
            green: comps[1] * factor,
            blue: comps[2] * factor,
            alpha: comps.count >= 4 ? comps[3] : 1.0)
    }
}
