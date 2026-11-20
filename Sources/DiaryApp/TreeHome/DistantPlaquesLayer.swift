import DiaryCore
import Foundation
import SwiftUI

struct DistantPlaqueEntry: Identifiable, Sendable {
    let entry: DiarySummary
    let anchor: PlaqueAnchor
    var id: UUID { entry.id }
}

/// Deterministic canopy distribution and single-pass Canvas LOD renderer for 100–1,000+ diaries.
enum TreeCanopyLOD {
    /// Golden-angle distribution across the tall canopy arch so hundreds/thousands of distant plaques
    /// spread naturally like lanterns/wooden charms without clumping or overlapping the lower trunk.
    static func distantSlots(
        entries: [DiarySummary],
        in size: CGSize,
        stage: TreeGrowthStage
    ) -> [DistantPlaqueEntry] {
        guard !entries.isEmpty else { return [] }
        let layout = TreeGeometry.layout(for: size, stage: stage)
        let goldenAngle = 2.3999632297286533  // radians
        let total = max(1, entries.count)

        var result: [DistantPlaqueEntry] = []
        result.reserveCapacity(entries.count)

        for (idx, entry) in entries.enumerated() {
            let frac = (Double(idx) + 0.5) / Double(total)
            let radius = sqrt(frac)
            let theta = Double(idx) * goldenAngle

            // Spread across the lush canopy arch (x: -410..410, y: -610..-235)
            let nx = CGFloat(cos(theta) * radius) * 410
            let ny = CGFloat(-420 + sin(theta) * radius * 195)
            let cord: CGFloat = 14 + CGFloat(idx % 5) * 2.5
            let phase = Double(idx) * 0.73

            result.append(
                DistantPlaqueEntry(
                    entry: entry,
                    anchor: PlaqueAnchor(
                        branchPoint: layout.point(nx, ny),
                        cordLength: cord * layout.scale,
                        phase: phase
                    )
                ))
        }
        return result
    }

    /// When zoomed in (>= 1.40x), promotes up to `limit` canopy entries currently inside the visible viewport
    /// into full interactive wooden plaques while keeping memory & layout O(1).
    static func visiblePromotedEntries(
        from slots: [DistantPlaqueEntry],
        viewportSize: CGSize,
        zoom: CGFloat,
        offset: CGSize,
        limit: Int = 10
    ) -> [DistantPlaqueEntry] {
        guard zoom >= 1.40, !slots.isEmpty else { return [] }
        let cx = viewportSize.width * 0.5
        let cy = viewportSize.height * 0.5
        let margin: CGFloat = 48

        var candidates: [(DistantPlaqueEntry, CGFloat)] = []
        candidates.reserveCapacity(min(slots.count, 32))

        for slot in slots {
            // Map canvas coordinate through scaleEffect(zoom) + offset(offset) into screen space.
            let sx = (slot.anchor.branchPoint.x - cx) * zoom + cx + offset.width
            let sy = (slot.anchor.branchPoint.y - cy) * zoom + cy + offset.height
            guard sx >= margin, sx <= viewportSize.width - margin,
                sy >= margin + 40, sy <= viewportSize.height - margin - 30
            else { continue }
            let distSq = (sx - cx) * (sx - cx) + (sy - cy) * (sy - cy)
            candidates.append((slot, distSq))
        }

        candidates.sort { $0.1 < $1.1 }
        return candidates.prefix(limit).map(\.0)
    }
}

/// Renders hundreds or thousands of distant canopy plaques in one fast 8-bit Canvas pass (< 1 ms).
struct DistantPlaquesCanvasView: View {
    let slots: [DistantPlaqueEntry]
    let excludedIDs: Set<UUID>
    let palette: TreeAtmospherePalette
    let isDark: Bool

    var body: some View {
        Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { context, _ in
            var cords = Path()
            var plainTags = Path()
            var privateTags = Path()

            for slot in slots {
                if excludedIDs.contains(slot.id) { continue }
                let p = slot.anchor.branchPoint
                let cordLen: CGFloat = 7.5
                cords.move(to: p)
                cords.addLine(to: CGPoint(x: p.x, y: p.y + cordLen))

                let tagRect = CGRect(x: p.x - 4.5, y: p.y + cordLen, width: 9.0, height: 12.0)
                let rounded = Path(roundedRect: tagRect, cornerRadius: 1.8)
                if slot.entry.isEncrypted {
                    privateTags.addPath(rounded)
                } else {
                    plainTags.addPath(rounded)
                }
            }

            context.stroke(
                cords,
                with: .color(palette.plaqueBorder.opacity(0.65)),
                lineWidth: 0.75)
            context.fill(plainTags, with: .color(palette.plaqueBackground.opacity(isDark ? 0.72 : 0.84)))
            context.stroke(
                plainTags,
                with: .color(palette.plaqueBorder.opacity(0.75)),
                lineWidth: 0.65)
            context.fill(privateTags, with: .color(DiaryStyle.accent.opacity(isDark ? 0.85 : 0.78)))
            context.stroke(
                privateTags,
                with: .color(palette.plaqueBorder.opacity(0.85)),
                lineWidth: 0.65)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
