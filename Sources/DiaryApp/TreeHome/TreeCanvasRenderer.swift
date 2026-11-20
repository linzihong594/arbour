import Foundation
import SwiftUI

/// Zero-offscreen-bitmap sky & celestial glow using native SwiftUI gradients.
struct TreeSkyBackdropView: View {
    let weatherKind: TreeWeatherKind
    let timeOfDay: TreeTimeOfDay
    let palette: TreeAtmospherePalette
    let isDark: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: palette.skyTop, location: 0.0),
                    .init(color: palette.skyMid, location: 0.54),
                    .init(color: palette.skyBottom, location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            if weatherKind == .clear {
                GeometryReader { proxy in
                    let norm = timeOfDay.celestialPosition
                    let center = CGPoint(x: proxy.size.width * norm.x, y: proxy.size.height * norm.y)
                    let outerRadius = min(proxy.size.width, proxy.size.height) * 0.22
                    let discSize: CGFloat = isDark ? 36 : 50

                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    palette.celestialColor.opacity(isDark ? 0.24 : 0.52),
                                    palette.celestialColor.opacity(isDark ? 0.06 : 0.14),
                                    .clear,
                                ],
                                center: .center,
                                startRadius: 6,
                                endRadius: outerRadius
                            )
                        )
                        .frame(width: outerRadius * 2, height: outerRadius * 2)
                        .position(center)

                    Circle()
                        .fill(palette.celestialColor.opacity(isDark ? 0.88 : 0.95))
                        .frame(width: discSize, height: discSize)
                        .position(center)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Lightweight native vector rolling hills and tree shadow (zero offscreen bitmap allocation).
struct TreeHillsLayerView: View {
    let layout: TreeGeometry.Layout
    let palette: TreeAtmospherePalette
    let isDark: Bool

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let pad: CGFloat = w * 0.35

            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: -pad, y: h * 0.85))
                    path.addCurve(
                        to: CGPoint(x: w + pad, y: h * 0.83),
                        control1: CGPoint(x: w * 0.28, y: h * 0.77),
                        control2: CGPoint(x: w * 0.72, y: h * 0.90))
                    path.addLine(to: CGPoint(x: w + pad, y: h + pad))
                    path.addLine(to: CGPoint(x: -pad, y: h + pad))
                    path.closeSubpath()
                }
                .fill(palette.hillFar)

                Path { path in
                    path.move(to: CGPoint(x: -pad, y: h * 0.90))
                    path.addCurve(
                        to: CGPoint(x: w + pad, y: h * 0.89),
                        control1: CGPoint(x: w * 0.35, y: h * 0.83),
                        control2: CGPoint(x: w * 0.65, y: h * 0.84))
                    path.addLine(to: CGPoint(x: w + pad, y: h + pad))
                    path.addLine(to: CGPoint(x: -pad, y: h + pad))
                    path.closeSubpath()
                }
                .fill(palette.hillNear)

                Ellipse()
                    .fill(Color.black.opacity(isDark ? 0.22 : 0.08))
                    .frame(width: 580 * layout.scale, height: 42 * layout.scale)
                    .position(x: layout.origin.x, y: layout.origin.y + 4 * layout.scale)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Composites the 4 pre-rendered botanical CGImage layers with multi-phase GPU wind sway.
struct TreeArtworkLayersView: View {
    let artwork: TreeArtworkSet
    let layout: TreeGeometry.Layout
    let windSpeedKmh: Double
    let time: Double
    let reduceMotion: Bool

    var body: some View {
        let wind = reduceMotion ? 0.0 : min(2.3, max(0.45, windSpeedKmh / 12.0))
        let gust = reduceMotion ? 0.0 : (1.0 + 0.30 * sin(time * 0.42) + 0.16 * sin(time * 1.07))

        let backDX = CGFloat(sin(time * 0.92 + 0.2) * 3.0 * wind * gust) * layout.scale
        let backRot = sin(time * 0.85) * 0.35 * wind * gust

        let midDX = CGFloat(sin(time * 1.18 + 1.1) * 4.6 * wind * gust) * layout.scale
        let midDY = CGFloat(cos(time * 0.95 + 0.8) * 1.4 * wind * gust) * layout.scale
        let midRot = sin(time * 1.05 + 0.6) * 0.55 * wind * gust

        let frontDX = CGFloat(sin(time * 1.42 + 2.1) * 6.4 * wind * gust) * layout.scale
        let frontDY = CGFloat(cos(time * 1.18 + 1.4) * 1.9 * wind * gust) * layout.scale
        let frontRot = sin(time * 1.25 + 1.4) * 0.80 * wind * gust

        let w = layout.artRect.width
        let h = layout.artRect.height
        let center = CGPoint(x: layout.artRect.midX, y: layout.artRect.midY)

        ZStack {
            sprite(artwork.backCanopy, width: w, height: h)
                .rotationEffect(.degrees(backRot), anchor: UnitPoint(x: 0.5, y: 0.72))
                .offset(x: backDX)

            sprite(artwork.trunkAndBranches, width: w, height: h)

            sprite(artwork.midCanopy, width: w, height: h)
                .rotationEffect(.degrees(midRot), anchor: UnitPoint(x: 0.5, y: 0.70))
                .offset(x: midDX, y: midDY)

            sprite(artwork.frontCanopy, width: w, height: h)
                .rotationEffect(.degrees(frontRot), anchor: UnitPoint(x: 0.5, y: 0.68))
                .offset(x: frontDX, y: frontDY)
        }
        .position(center)
        .accessibilityHidden(true)
    }

    private func sprite(_ image: CGImage, width: CGFloat, height: CGFloat) -> some View {
        Image(decorative: image, scale: 1.0)
            .resizable()
            .interpolation(.medium)
            .frame(width: width, height: height)
    }
}

/// Lightweight 8-bit sRGB weather overlay (clouds, rain, snow, fog, sunlit motes, drifting leaves).
struct TreeWeatherOverlayView: View {
    let weatherKind: TreeWeatherKind
    let windSpeedKmh: Double
    let palette: TreeAtmospherePalette
    let time: Double
    let isDark: Bool

    var body: some View {
        // Use standard 8-bit .nonLinear sRGB and synchronous rendering to avoid 64-bit swapchain memory bloat.
        Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
            let windFactor = min(2.4, max(0.45, windSpeedKmh / 12.0))
            drawStormFlashIfNeeded(in: &context, size: size)
            drawClouds(in: &context, size: size, windFactor: windFactor)
            drawWeatherEffects(in: &context, size: size, windFactor: windFactor)
        }
        .accessibilityHidden(true)
    }

    private func drawStormFlashIfNeeded(in context: inout GraphicsContext, size: CGSize) {
        guard weatherKind == .thunderstorm else { return }
        let cycle = time.truncatingRemainder(dividingBy: 9.5)
        let flash: Double =
            (cycle > 7.8 && cycle < 7.96)
            ? 0.13 : (cycle > 8.05 && cycle < 8.15 ? 0.07 : 0.0)
        if flash > 0 {
            context.fill(
                Path(CGRect(origin: .zero, size: size)), with: .color(Color.white.opacity(flash)))
        }
    }

    private func drawClouds(
        in context: inout GraphicsContext, size: CGSize, windFactor: Double
    ) {
        let cloudCount: Int
        switch weatherKind {
        case .clear: cloudCount = 2
        case .cloudy, .snow: cloudCount = 4
        case .fog: cloudCount = 3
        case .rain, .thunderstorm: cloudCount = 5
        }

        for idx in 0..<cloudCount {
            let seed = Self.cloudSeeds[idx]
            let span = size.width + 340
            let drift = (seed.x * span + time * seed.speed * (0.7 + windFactor * 0.35))
                .truncatingRemainder(dividingBy: span)
            let cx = drift - 170
            let cy = size.height * seed.y
            drawCloud(
                in: &context, center: CGPoint(x: cx, y: cy), scale: seed.scale,
                opacity: weatherKind == .clear ? 0.45 : 0.85)
        }
    }

    private func drawCloud(
        in context: inout GraphicsContext, center: CGPoint, scale: CGFloat, opacity: Double
    ) {
        func pt(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint {
            CGPoint(x: center.x + dx * scale, y: center.y + dy * scale)
        }
        var cloud = Path()
        cloud.move(to: pt(-68, 16))
        cloud.addCurve(to: pt(-48, -6), control1: pt(-78, 6), control2: pt(-66, -8))
        cloud.addCurve(to: pt(-6, -24), control1: pt(-42, -22), control2: pt(-20, -28))
        cloud.addCurve(to: pt(40, -10), control1: pt(12, -24), control2: pt(30, -22))
        cloud.addCurve(to: pt(72, 16), control1: pt(60, -8), control2: pt(78, 4))
        cloud.addQuadCurve(to: pt(-68, 16), control: pt(2, 22))
        cloud.closeSubpath()

        let grad = Gradient(colors: [
            palette.cloudColor.opacity(opacity),
            palette.cloudColor.opacity(opacity * 0.45),
        ])
        context.fill(
            cloud,
            with: .linearGradient(grad, startPoint: pt(0, -24), endPoint: pt(0, 20)))
    }

    private func drawWeatherEffects(
        in context: inout GraphicsContext, size: CGSize, windFactor: Double
    ) {
        switch weatherKind {
        case .clear:
            drawSunlightMotes(in: &context, size: size, windFactor: windFactor)
            drawDriftingLeaves(in: &context, size: size, windFactor: windFactor)
        case .cloudy:
            drawDriftingLeaves(in: &context, size: size, windFactor: windFactor)
        case .fog:
            drawFogBands(in: &context, size: size)
        case .rain:
            drawRain(in: &context, size: size, windFactor: windFactor, count: 36, heavy: false)
        case .thunderstorm:
            drawRain(in: &context, size: size, windFactor: windFactor, count: 48, heavy: true)
        case .snow:
            drawSnow(in: &context, size: size, windFactor: windFactor)
        }
    }

    private func drawSunlightMotes(
        in context: inout GraphicsContext, size: CGSize, windFactor: Double
    ) {
        var dots = Path()
        for mote in Self.moteSeeds {
            let x =
                (mote.x * size.width + time * (7 * windFactor) + sin(time * 0.75 + mote.phase) * 16)
                .truncatingRemainder(dividingBy: max(1, size.width))
            let y =
                (mote.y * size.height + sin(time * 0.45 + mote.phase) * 20)
                .truncatingRemainder(dividingBy: max(1, size.height))
            let r = mote.size
            dots.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        }
        context.fill(dots, with: .color(palette.precipitationColor.opacity(0.42)))
    }

    private func drawDriftingLeaves(
        in context: inout GraphicsContext, size: CGSize, windFactor: Double
    ) {
        for idx in 0..<3 {
            let phase = Double(idx) * 2.4 + 0.5
            let progress = ((time * 0.085 + Double(idx) * 0.33)).truncatingRemainder(dividingBy: 1.0)
            let startX = size.width * (0.28 + CGFloat(idx) * 0.22)
            let x =
                startX + CGFloat(progress) * 160 * CGFloat(windFactor)
                + sin(time * 1.8 + phase) * 26
            let y = size.height * (0.18 + CGFloat(progress) * 0.72)
            let alpha = sin(progress * .pi) * 0.82
            let rot = time * 1.15 + phase

            context.drawLayer { layer in
                layer.translateBy(x: x, y: y)
                layer.rotate(by: .radians(rot))
                var leaf = Path()
                leaf.move(to: CGPoint(x: -6.5, y: 0))
                leaf.addQuadCurve(to: CGPoint(x: 6.5, y: 0), control: CGPoint(x: 0, y: -4.2))
                leaf.addQuadCurve(to: CGPoint(x: -6.5, y: 0), control: CGPoint(x: 0, y: 4.2))
                leaf.closeSubpath()
                layer.fill(leaf, with: .color(palette.leafAccent.opacity(alpha)))
            }
        }
    }

    private func drawFogBands(in context: inout GraphicsContext, size: CGSize) {
        for idx in 0..<3 {
            let y = size.height * (0.56 + CGFloat(idx) * 0.14)
            let drift = sin(time * (0.18 + Double(idx) * 0.07) + Double(idx)) * 70
            let bandRect = CGRect(
                x: -100 + drift, y: y, width: size.width + 200, height: size.height * 0.16)
            let grad = Gradient(colors: [
                palette.precipitationColor.opacity(0),
                palette.precipitationColor.opacity(isDark ? 0.14 : 0.36),
                palette.precipitationColor.opacity(0),
            ])
            context.fill(
                Path(ellipseIn: bandRect),
                with: .linearGradient(
                    grad,
                    startPoint: CGPoint(x: bandRect.midX, y: bandRect.minY),
                    endPoint: CGPoint(x: bandRect.midX, y: bandRect.maxY)))
        }
    }

    private func drawRain(
        in context: inout GraphicsContext,
        size: CGSize,
        windFactor: Double,
        count: Int,
        heavy: Bool
    ) {
        let slant = CGFloat(4.5 * windFactor)
        let speed: Double = heavy ? 540 : 400
        let dropLength: CGFloat = heavy ? 24 : 17
        var streaks = Path()

        for idx in 0..<min(count, Self.particleSeeds.count) {
            let p = Self.particleSeeds[idx]
            let yRaw = (p.y * Double(size.height) + time * speed * p.speed)
                .truncatingRemainder(dividingBy: Double(size.height + 60))
            let y = CGFloat(yRaw) - 30
            let xRaw = (p.x * Double(size.width) + time * Double(slant) * 14 * p.speed)
                .truncatingRemainder(dividingBy: Double(size.width + 80))
            let x = CGFloat(xRaw) - 40
            streaks.move(to: CGPoint(x: x, y: y))
            streaks.addLine(to: CGPoint(x: x + slant, y: y + dropLength))
        }

        context.stroke(
            streaks,
            with: .color(palette.precipitationColor.opacity(heavy ? 0.55 : 0.44)),
            style: StrokeStyle(lineWidth: heavy ? 1.35 : 1.1, lineCap: .round))

        for idx in 0..<6 {
            let p = Self.particleSeeds[idx]
            let cycle = (time * 1.05 + p.phase).truncatingRemainder(dividingBy: 1.0)
            let rx = p.x * size.width * 0.8 + size.width * 0.1
            let ry = size.height * (0.86 + p.y * 0.10)
            let radius = CGFloat(cycle) * 18
            let alpha = (1.0 - cycle) * 0.28
            context.stroke(
                Path(
                    ellipseIn: CGRect(
                        x: rx - radius, y: ry - radius * 0.35,
                        width: radius * 2, height: radius * 0.7)),
                with: .color(palette.precipitationColor.opacity(alpha)),
                lineWidth: 1.0)
        }
    }

    private func drawSnow(
        in context: inout GraphicsContext, size: CGSize, windFactor: Double
    ) {
        var flakes = Path()
        for idx in 0..<32 {
            let p = Self.particleSeeds[idx]
            let yRaw = (p.y * Double(size.height) + time * (40 * p.speed))
                .truncatingRemainder(dividingBy: Double(size.height + 30))
            let y = CGFloat(yRaw) - 15
            let drift = sin(time * 1.1 + p.phase) * 18 + time * 14 * windFactor
            let xRaw = (p.x * Double(size.width) + drift)
                .truncatingRemainder(dividingBy: Double(size.width + 40))
            let x = CGFloat(xRaw < 0 ? xRaw + Double(size.width + 40) : xRaw) - 20
            let r = p.size * 1.65
            flakes.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        }
        context.fill(flakes, with: .color(palette.precipitationColor.opacity(0.78)))
    }

    private struct CloudSeed {
        let x: Double
        let y: CGFloat
        let scale: CGFloat
        let speed: Double
    }

    private struct ParticleSeed {
        let x: Double
        let y: Double
        let speed: Double
        let size: CGFloat
        let phase: Double
    }

    private static let cloudSeeds: [CloudSeed] = [
        CloudSeed(x: 0.14, y: 0.12, scale: 1.0, speed: 6.5),
        CloudSeed(x: 0.56, y: 0.09, scale: 0.82, speed: 4.8),
        CloudSeed(x: 0.84, y: 0.17, scale: 1.08, speed: 5.6),
        CloudSeed(x: 0.34, y: 0.20, scale: 0.74, speed: 7.4),
        CloudSeed(x: 0.70, y: 0.14, scale: 0.90, speed: 6.1),
    ]

    private static let moteSeeds: [ParticleSeed] = (0..<12).map { i in
        let fi = Double(i)
        return ParticleSeed(
            x: ((fi * 0.37 + 0.11).truncatingRemainder(dividingBy: 1.0)),
            y: ((fi * 0.29 + 0.15).truncatingRemainder(dividingBy: 0.72)),
            speed: 0.7 + (fi.truncatingRemainder(dividingBy: 3)) * 0.2,
            size: CGFloat(1.7 + (fi.truncatingRemainder(dividingBy: 3)) * 0.7),
            phase: fi * 1.15
        )
    }

    private static let particleSeeds: [ParticleSeed] = (0..<50).map { i in
        let fi = Double(i)
        return ParticleSeed(
            x: ((fi * 0.6180339887).truncatingRemainder(dividingBy: 1.0)),
            y: ((fi * 0.3819660113).truncatingRemainder(dividingBy: 1.0)),
            speed: 0.78 + ((fi * 0.27).truncatingRemainder(dividingBy: 0.52)),
            size: CGFloat(1.4 + ((fi * 0.43).truncatingRemainder(dividingBy: 1.5))),
            phase: fi * 0.93
        )
    }
}
