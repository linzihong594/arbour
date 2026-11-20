import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func cubicPoint(_ p0: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ p3: CGPoint, t: CGFloat) -> CGPoint {
    let u = 1 - t
    let uu = u * u
    let tt = t * t
    let x = uu * u * p0.x + 3 * uu * t * c1.x + 3 * u * tt * c2.x + tt * t * p3.x
    let y = uu * u * p0.y + 3 * uu * t * c1.y + 3 * u * tt * c2.y + tt * t * p3.y
    return CGPoint(x: x, y: y)
}

func cubicTangent(_ p0: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ p3: CGPoint, t: CGFloat) -> CGPoint {
    let u = 1 - t
    let dx = 3 * u * u * (c1.x - p0.x) + 6 * u * t * (c2.x - c1.x) + 3 * t * t * (p3.x - c2.x)
    let dy = 3 * u * u * (c1.y - p0.y) + 6 * u * t * (c2.y - c1.y) + 3 * t * t * (p3.y - c2.y)
    let len = max(0.001, hypot(dx, dy))
    return CGPoint(x: dx / len, y: dy / len)
}

func drawTaperedBranch(
    in ctx: CGContext,
    p0: CGPoint, c1: CGPoint, c2: CGPoint, p3: CGPoint,
    startWidth: CGFloat, endWidth: CGFloat,
    fillColor: NSColor,
    rimColor: NSColor? = nil
) {
    let steps = 28
    var leftPts: [CGPoint] = []
    var rightPts: [CGPoint] = []
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps)
        let pt = cubicPoint(p0, c1, c2, p3, t: t)
        let tan = cubicTangent(p0, c1, c2, p3, t: t)
        let normal = CGPoint(x: -tan.y, y: tan.x)
        let halfW = (startWidth + (endWidth - startWidth) * pow(t, 0.85)) * 0.5
        leftPts.append(CGPoint(x: pt.x + normal.x * halfW, y: pt.y + normal.y * halfW))
        rightPts.append(CGPoint(x: pt.x - normal.x * halfW, y: pt.y - normal.y * halfW))
    }

    let path = CGMutablePath()
    path.move(to: leftPts[0])
    for pt in leftPts.dropFirst() { path.addLine(to: pt) }
    for pt in rightPts.reversed() { path.addLine(to: pt) }
    path.closeSubpath()

    ctx.saveGState()
    ctx.addPath(path)
    ctx.setFillColor(fillColor.cgColor)
    ctx.fillPath()

    if let rimColor {
        let rim = CGMutablePath()
        rim.move(to: leftPts[0])
        for pt in leftPts.dropFirst() { rim.addLine(to: pt) }
        ctx.addPath(rim)
        ctx.setStrokeColor(rimColor.cgColor)
        ctx.setLineWidth(3.2)
        ctx.setLineCap(.round)
        ctx.strokePath()
    }
    ctx.restoreGState()
}

func drawPointedLeaf(
    in ctx: CGContext,
    origin: CGPoint,
    angle: CGFloat,
    length: CGFloat,
    width: CGFloat,
    color: NSColor
) {
    ctx.saveGState()
    ctx.translateBy(x: origin.x, y: origin.y)
    ctx.rotate(by: angle)

    let leaf = CGMutablePath()
    leaf.move(to: .zero)
    leaf.addQuadCurve(
        to: CGPoint(x: length, y: 0),
        control: CGPoint(x: length * 0.44, y: width)
    )
    leaf.addQuadCurve(
        to: .zero,
        control: CGPoint(x: length * 0.44, y: -width)
    )
    leaf.closeSubpath()

    ctx.addPath(leaf)
    ctx.setFillColor(color.cgColor)
    ctx.fillPath()
    ctx.restoreGState()
}

func drawRadialGlow(in ctx: CGContext, center: CGPoint, radius: CGFloat, colors: [NSColor], locations: [CGFloat]) {
    let cs = CGColorSpaceCreateDeviceRGB()
    let cgColors = colors.map(\.cgColor) as CFArray
    if let grad = CGGradient(colorsSpace: cs, colors: cgColors, locations: locations) {
        ctx.drawRadialGradient(
            grad,
            startCenter: center, startRadius: 0,
            endCenter: center, endRadius: radius,
            options: [.drawsAfterEndLocation]
        )
    }
}

func drawIcon(pixels: Int) throws -> Data {
    guard
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let graphics = NSGraphicsContext(bitmapImageRep: bitmap)
    else {
        throw CocoaError(.fileWriteUnknown)
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    defer { NSGraphicsContext.restoreGraphicsState() }

    let ctx = graphics.cgContext
    let scale = CGFloat(pixels) / 1024.0
    ctx.scaleBy(x: scale, y: scale)
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)

    // macOS standard squircle icon bounds inside 1024x1024 canvas
    let iconRect = NSRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = NSBezierPath(roundedRect: iconRect, xRadius: 185, yRadius: 185)

    // Subtle elevation shadow behind the icon tile
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -14),
        blur: 28,
        color: NSColor.black.withAlphaComponent(0.32).cgColor
    )
    NSColor(red: 0.08, green: 0.13, blue: 0.19, alpha: 1).setFill()
    squircle.fill()
    ctx.restoreGState()

    // Clip all artwork cleanly inside the squircle
    ctx.saveGState()
    squircle.addClip()

    // 1. Deep twilight-to-midnight indigo sky gradient
    let skyGradient = NSGradient(colorsAndLocations:
        (NSColor(red: 0.13, green: 0.21, blue: 0.30, alpha: 1.0), 0.0),
        (NSColor(red: 0.09, green: 0.15, blue: 0.23, alpha: 1.0), 0.52),
        (NSColor(red: 0.05, green: 0.09, blue: 0.15, alpha: 1.0), 1.0)
    )!
    skyGradient.draw(in: iconRect, angle: -65)

    // 2. Soft moonlight atmospheric halo in upper-right sky
    let moonCenter = CGPoint(x: 716, y: 726)
    drawRadialGlow(
        in: ctx,
        center: moonCenter,
        radius: 390,
        colors: [
            NSColor(red: 0.98, green: 0.92, blue: 0.74, alpha: 0.30),
            NSColor(red: 0.85, green: 0.82, blue: 0.68, alpha: 0.10),
            NSColor(red: 0.10, green: 0.16, blue: 0.24, alpha: 0.0),
        ],
        locations: [0.0, 0.45, 1.0]
    )

    // 3. Quiet distant starlight pinpoints
    let stars: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
        (235, 815, 3.6, 0.55),
        (332, 855, 2.6, 0.38),
        (468, 822, 3.0, 0.45),
        (212, 682, 2.4, 0.32),
        (824, 596, 2.8, 0.40),
        (850, 818, 2.4, 0.36),
    ]
    for (sx, sy, sr, sa) in stars {
        ctx.setFillColor(NSColor(red: 0.97, green: 0.95, blue: 0.86, alpha: sa).cgColor)
        ctx.fillEllipse(in: CGRect(x: sx - sr, y: sy - sr, width: sr * 2, height: sr * 2))
    }

    // 4. Luminous crescent-tinted full moon
    let moonRadius: CGFloat = 76
    let moonRect = CGRect(
        x: moonCenter.x - moonRadius, y: moonCenter.y - moonRadius,
        width: moonRadius * 2, height: moonRadius * 2
    )
    ctx.saveGState()
    ctx.addEllipse(in: moonRect)
    ctx.clip()
    let moonGrad = NSGradient(
        starting: NSColor(red: 1.0, green: 0.99, blue: 0.93, alpha: 1.0),
        ending: NSColor(red: 0.93, green: 0.84, blue: 0.63, alpha: 1.0)
    )!
    moonGrad.draw(in: moonRect, angle: -45)
    ctx.restoreGState()

    // 5. Soft rolling pine-slate hills at the bottom to ground the scene
    let farHill = CGMutablePath()
    farHill.move(to: CGPoint(x: 90, y: 90))
    farHill.addLine(to: CGPoint(x: 90, y: 265))
    farHill.addQuadCurve(to: CGPoint(x: 940, y: 230), control: CGPoint(x: 490, y: 315))
    farHill.addLine(to: CGPoint(x: 940, y: 90))
    farHill.closeSubpath()
    ctx.addPath(farHill)
    ctx.setFillColor(NSColor(red: 0.08, green: 0.14, blue: 0.17, alpha: 0.92).cgColor)
    ctx.fillPath()

    let nearHill = CGMutablePath()
    nearHill.move(to: CGPoint(x: 90, y: 90))
    nearHill.addLine(to: CGPoint(x: 90, y: 205))
    nearHill.addQuadCurve(to: CGPoint(x: 940, y: 185), control: CGPoint(x: 610, y: 255))
    nearHill.addLine(to: CGPoint(x: 940, y: 90))
    nearHill.closeSubpath()
    ctx.addPath(nearHill)
    ctx.setFillColor(NSColor(red: 0.06, green: 0.11, blue: 0.13, alpha: 1.0).cgColor)
    ctx.fillPath()

    // 6. Back foliage leaves (deeper twilight sage & muted olive behind the bough)
    let backLeaves: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, NSColor)] = [
        (195, 650, 2.35, 92, 26, NSColor(red: 0.15, green: 0.25, blue: 0.24, alpha: 0.88)),
        (240, 680, 1.85, 86, 24, NSColor(red: 0.18, green: 0.29, blue: 0.26, alpha: 0.85)),
        (315, 705, 1.25, 82, 23, NSColor(red: 0.20, green: 0.31, blue: 0.27, alpha: 0.86)),
        (385, 735, 0.85, 78, 22, NSColor(red: 0.22, green: 0.34, blue: 0.29, alpha: 0.82)),
        (275, 595, -2.40, 84, 23, NSColor(red: 0.14, green: 0.23, blue: 0.22, alpha: 0.88)),
        (355, 610, -1.95, 78, 22, NSColor(red: 0.17, green: 0.27, blue: 0.25, alpha: 0.85)),
        (450, 665, 0.55, 74, 21, NSColor(red: 0.23, green: 0.35, blue: 0.30, alpha: 0.80)),
        (595, 652, 0.35, 68, 19, NSColor(red: 0.26, green: 0.37, blue: 0.31, alpha: 0.78)),
    ]
    for (x, y, ang, len, w, col) in backLeaves {
        drawPointedLeaf(in: ctx, origin: CGPoint(x: x, y: y), angle: ang, length: len, width: w, color: col)
    }

    // 7. Graceful organic main bough & secondary moonlit shoots sweeping from left
    let mainP0 = CGPoint(x: 92, y: 582)
    let mainC1 = CGPoint(x: 245, y: 618)
    let mainC2 = CGPoint(x: 425, y: 642)
    let mainP3 = CGPoint(x: 655, y: 616)

    // Upper reaching shoot toward the moon
    drawTaperedBranch(
        in: ctx,
        p0: CGPoint(x: 280, y: 626),
        c1: CGPoint(x: 345, y: 690),
        c2: CGPoint(x: 425, y: 744),
        p3: CGPoint(x: 522, y: 766),
        startWidth: 22, endWidth: 6.5,
        fillColor: NSColor(red: 0.21, green: 0.17, blue: 0.16, alpha: 1.0),
        rimColor: NSColor(red: 0.68, green: 0.60, blue: 0.48, alpha: 0.42)
    )

    // Lower delicate twig on the left
    drawTaperedBranch(
        in: ctx,
        p0: CGPoint(x: 205, y: 604),
        c1: CGPoint(x: 255, y: 558),
        c2: CGPoint(x: 315, y: 528),
        p3: CGPoint(x: 378, y: 522),
        startWidth: 16, endWidth: 5.0,
        fillColor: NSColor(red: 0.19, green: 0.15, blue: 0.14, alpha: 1.0),
        rimColor: NSColor(red: 0.55, green: 0.48, blue: 0.40, alpha: 0.28)
    )

    // Main hero branch
    drawTaperedBranch(
        in: ctx,
        p0: mainP0, c1: mainC1, c2: mainC2, p3: mainP3,
        startWidth: 44, endWidth: 11,
        fillColor: NSColor(red: 0.24, green: 0.19, blue: 0.18, alpha: 1.0),
        rimColor: NSColor(red: 0.78, green: 0.69, blue: 0.54, alpha: 0.52)
    )

    // 8. Front moonlit botanical leaves (emerald-sage + warm gilded autumn highlights)
    let frontLeaves: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, NSColor)] = [
        (165, 616, 2.10, 88, 24, NSColor(red: 0.24, green: 0.40, blue: 0.34, alpha: 0.94)),
        (225, 646, 1.48, 84, 22, NSColor(red: 0.30, green: 0.48, blue: 0.39, alpha: 0.92)),
        (332, 692, 1.08, 78, 21, NSColor(red: 0.36, green: 0.53, blue: 0.42, alpha: 0.92)),
        (415, 738, 0.52, 74, 20, NSColor(red: 0.72, green: 0.56, blue: 0.34, alpha: 0.90)),
        (485, 760, 0.18, 68, 18, NSColor(red: 0.85, green: 0.69, blue: 0.42, alpha: 0.92)),
        (365, 712, 2.30, 68, 18, NSColor(red: 0.28, green: 0.44, blue: 0.36, alpha: 0.88)),
        (255, 560, -2.05, 74, 20, NSColor(red: 0.22, green: 0.36, blue: 0.31, alpha: 0.92)),
        (322, 530, -1.20, 68, 18, NSColor(red: 0.32, green: 0.46, blue: 0.37, alpha: 0.88)),
        (368, 522, -0.35, 62, 17, NSColor(red: 0.76, green: 0.59, blue: 0.35, alpha: 0.88)),
        (585, 626, 0.48, 70, 18, NSColor(red: 0.78, green: 0.62, blue: 0.37, alpha: 0.90)),
        (638, 618, 0.08, 66, 17, NSColor(red: 0.88, green: 0.74, blue: 0.47, alpha: 0.94)),
        (612, 616, -0.78, 60, 16, NSColor(red: 0.34, green: 0.50, blue: 0.40, alpha: 0.88)),
    ]
    for (x, y, ang, len, w, col) in frontLeaves {
        drawPointedLeaf(in: ctx, origin: CGPoint(x: x, y: y), angle: ang, length: len, width: w, color: col)
    }

    // 9. Hero Hanging Wooden Plaque (暖光木牌) suspended from the main bough
    let hangPoint = cubicPoint(mainP0, mainC1, mainC2, mainP3, t: 0.76)

    // Warm candlelight halo behind the wooden plaque
    drawRadialGlow(
        in: ctx,
        center: CGPoint(x: hangPoint.x + 8, y: hangPoint.y - 210),
        radius: 265,
        colors: [
            NSColor(red: 0.98, green: 0.86, blue: 0.60, alpha: 0.28),
            NSColor(red: 0.94, green: 0.78, blue: 0.48, alpha: 0.08),
            NSColor(red: 0.10, green: 0.15, blue: 0.22, alpha: 0.0),
        ],
        locations: [0.0, 0.50, 1.0]
    )

    // Subtle wind-swayed pendulum transform anchored right at the branch knot
    ctx.saveGState()
    ctx.translateBy(x: hangPoint.x, y: hangPoint.y)
    ctx.rotate(by: -0.075)  // gentle ~4.3 deg breeze tilt

    let cordLength: CGFloat = 78
    let plaqueW: CGFloat = 236
    let plaqueH: CGFloat = 296
    let plaqueRect = CGRect(x: -plaqueW * 0.5, y: -cordLength - plaqueH, width: plaqueW, height: plaqueH)

    // Linen hanging cord
    ctx.setStrokeColor(NSColor(red: 0.87, green: 0.77, blue: 0.58, alpha: 0.95).cgColor)
    ctx.setLineWidth(5.5)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: 0, y: 2))
    ctx.addLine(to: CGPoint(x: 0, y: -cordLength - 18))
    ctx.strokePath()

    // Branch knot bead
    ctx.setFillColor(NSColor(red: 0.86, green: 0.74, blue: 0.53, alpha: 1.0).cgColor)
    ctx.fillEllipse(in: CGRect(x: -8.5, y: -8.5, width: 17, height: 17))
    ctx.setFillColor(NSColor(red: 0.25, green: 0.19, blue: 0.17, alpha: 1.0).cgColor)
    ctx.fillEllipse(in: CGRect(x: -4, y: -4, width: 8, height: 8))

    // Plaque drop shadow
    let plaquePath = NSBezierPath(roundedRect: plaqueRect, xRadius: 28, yRadius: 28)
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -16),
        blur: 32,
        color: NSColor.black.withAlphaComponent(0.45).cgColor
    )
    NSColor(red: 0.97, green: 0.93, blue: 0.84, alpha: 1.0).setFill()
    plaquePath.fill()
    ctx.restoreGState()

    // Plaque warm parchment-wood gradient fill
    ctx.saveGState()
    plaquePath.addClip()
    let plaqueGrad = NSGradient(
        starting: NSColor(red: 0.99, green: 0.97, blue: 0.91, alpha: 1.0),
        ending: NSColor(red: 0.92, green: 0.84, blue: 0.70, alpha: 1.0)
    )!
    plaqueGrad.draw(in: plaqueRect, angle: -82)

    // Subtle warm top sheen inside plaque
    let topSheen = CGRect(x: plaqueRect.minX, y: plaqueRect.maxY - 64, width: plaqueW, height: 64)
    NSGradient(
        starting: NSColor.white.withAlphaComponent(0.32),
        ending: NSColor.white.withAlphaComponent(0.0)
    )!.draw(in: topSheen, angle: -90)
    ctx.restoreGState()

    // Refined wooden-gold border
    NSColor(red: 0.78, green: 0.65, blue: 0.45, alpha: 0.90).setStroke()
    plaquePath.lineWidth = 4.0
    plaquePath.stroke()

    // Inner recessed frame line
    let innerRect = plaqueRect.insetBy(dx: 14, dy: 14)
    let innerPath = NSBezierPath(roundedRect: innerRect, xRadius: 18, yRadius: 18)
    NSColor(red: 0.74, green: 0.61, blue: 0.42, alpha: 0.30).setStroke()
    innerPath.lineWidth = 2.0
    innerPath.stroke()

    // Brass eyelet hole at top center of plaque
    let holeCenter = CGPoint(x: 0, y: plaqueRect.maxY - 26)
    ctx.setFillColor(NSColor(red: 0.14, green: 0.21, blue: 0.28, alpha: 0.95).cgColor)
    ctx.fillEllipse(in: CGRect(x: holeCenter.x - 10, y: holeCenter.y - 10, width: 20, height: 20))
    ctx.setStrokeColor(NSColor(red: 0.78, green: 0.64, blue: 0.43, alpha: 1.0).cgColor)
    ctx.setLineWidth(3.5)
    ctx.strokeEllipse(in: CGRect(x: holeCenter.x - 10, y: holeCenter.y - 10, width: 20, height: 20))

    // Minimalist poetic ink strokes on the wooden plaque (evoking a quiet diary note)
    let inkColor = NSColor(red: 0.32, green: 0.27, blue: 0.22, alpha: 0.72)
    let lineSpecs: [(CGFloat, CGFloat, CGFloat)] = [
        (plaqueRect.maxY - 94, 128, 11.0),
        (plaqueRect.maxY - 134, 142, 9.5),
        (plaqueRect.maxY - 172, 108, 9.5),
    ]
    for (ly, lw, thick) in lineSpecs {
        let line = NSBezierPath()
        line.move(to: NSPoint(x: -71, y: ly))
        line.line(to: NSPoint(x: -71 + lw, y: ly))
        inkColor.setStroke()
        line.lineWidth = thick
        line.lineCapStyle = .round
        line.stroke()
    }

    // Small sage-green botanical leaf seal at bottom-right of the plaque
    drawPointedLeaf(
        in: ctx,
        origin: CGPoint(x: 24, y: plaqueRect.minY + 46),
        angle: 0.68,
        length: 44,
        width: 14,
        color: NSColor(red: 0.34, green: 0.50, blue: 0.39, alpha: 0.92)
    )
    drawPointedLeaf(
        in: ctx,
        origin: CGPoint(x: 26, y: plaqueRect.minY + 44),
        angle: 1.55,
        length: 30,
        width: 10,
        color: NSColor(red: 0.45, green: 0.60, blue: 0.46, alpha: 0.85)
    )

    ctx.restoreGState()

    // 10. Crisp macOS inner glass rim border for Dock polish
    let rimPath = NSBezierPath(roundedRect: iconRect.insetBy(dx: 1.5, dy: 1.5), xRadius: 183.5, yRadius: 183.5)
    NSColor.white.withAlphaComponent(0.14).setStroke()
    rimPath.lineWidth = 3.0
    rimPath.stroke()

    ctx.restoreGState()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return png
}

for points in [16, 32, 128, 256, 512] {
    for density in [1, 2] {
        let suffix = density == 2 ? "@2x" : ""
        let filename = "icon_\(points)x\(points)\(suffix).png"
        try drawIcon(pixels: points * density).write(to: output.appendingPathComponent(filename))
    }
}
