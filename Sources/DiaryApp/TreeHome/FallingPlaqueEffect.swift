import Foundation
import SwiftUI

struct FallingPlaqueItem: Identifiable, Sendable {
    let id: UUID
    let title: String
    let dateText: String
    let isEncrypted: Bool
    let startPoint: CGPoint
    let groundY: CGFloat
    let startedAt: Date
    let windSpeedKmh: Double
}

/// Decoupled 60 FPS one-shot animation: detached wooden plaque falls to the grass and dissolves cleanly.
/// Must be placed OUTSIDE the tree's lower-FPS TimelineView so it never drops frames.
struct FallingPlaqueOverlayView: View {
    static let totalDuration: TimeInterval = 1.40

    let items: [FallingPlaqueItem]
    let palette: TreeAtmospherePalette
    let isDark: Bool
    let onFinish: (UUID) -> Void

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let now = timeline.date
            ZStack {
                ForEach(items) { item in
                    fallingUnit(for: item, elapsed: max(0, now.timeIntervalSince(item.startedAt)))
                }
            }
        }
        .onAppear { scheduleCleanups() }
        .onChange(of: items.count) { _, _ in scheduleCleanups() }
        .allowsHitTesting(false)
    }

    private func scheduleCleanups() {
        let now = Date.now
        for item in items {
            let remaining = max(0.05, Self.totalDuration - now.timeIntervalSince(item.startedAt) + 0.05)
            let itemID = item.id
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(remaining))
                onFinish(itemID)
            }
        }
    }

    private func fallingUnit(for item: FallingPlaqueItem, elapsed: TimeInterval) -> some View {
        let fallDuration: Double = 0.58
        let restEnd: Double = 0.76
        let dissolveDuration: Double = Self.totalDuration - restEnd

        let dropDistance = max(40, item.groundY - item.startPoint.y)
        let windDrift = CGFloat(min(1.8, max(0.5, item.windSpeedKmh / 12.0))) * 24

        let yPos: CGFloat
        let xPos: CGFloat
        let rotation: Double
        let plaqueOpacity: Double
        let plaqueScale: CGFloat

        if elapsed < fallDuration {
            let p = elapsed / fallDuration
            yPos = item.startPoint.y + dropDistance * CGFloat(p * p)
            xPos = item.startPoint.x + windDrift * CGFloat(p) + CGFloat(sin(p * .pi * 2.0) * 7)
            rotation = sin(p * .pi * 1.4) * 24 + p * 16
            plaqueOpacity = 1.0
            plaqueScale = 1.0
        } else if elapsed < restEnd {
            let p = (elapsed - fallDuration) / (restEnd - fallDuration)
            let bounce = sin(p * .pi) * 8.0 * (1.0 - p * 0.5)
            yPos = item.groundY - CGFloat(bounce)
            xPos = item.startPoint.x + windDrift
            rotation = 16 - p * 5
            plaqueOpacity = 1.0
            plaqueScale = 1.0
        } else {
            let p = min(1.0, (elapsed - restEnd) / dissolveDuration)
            yPos = item.groundY
            xPos = item.startPoint.x + windDrift
            rotation = 11
            plaqueOpacity = max(0, 1.0 - p * 1.4)
            plaqueScale = CGFloat(1.0 - p * 0.14)
        }

        return ZStack {
            if plaqueOpacity > 0.01 {
                detachedPlaqueCard(item: item)
                    .scaleEffect(plaqueScale)
                    .rotationEffect(.degrees(rotation))
                    .opacity(plaqueOpacity)
                    .position(x: xPos, y: yPos)
            }

            if elapsed >= restEnd {
                let dp = min(1.0, (elapsed - restEnd) / dissolveDuration)
                let fade = sin(dp * .pi)
                ForEach(0..<10, id: \.self) { idx in
                    let f = Double(idx)
                    let dx =
                        CGFloat((f - 4.5) * 8.0) + windDrift * CGFloat(dp)
                        + CGFloat(sin(f * 2.1 + dp * 4.0) * 10)
                    let dy = -CGFloat(dp * (32 + (f.truncatingRemainder(dividingBy: 3)) * 16))
                    let d = CGFloat((4.5 + f.truncatingRemainder(dividingBy: 3.0)) * (1.0 - dp * 0.45))
                    Circle()
                        .fill(idx.isMultiple(of: 3) ? palette.leafAccent : palette.plaqueBorder)
                        .frame(width: d, height: d)
                        .opacity(fade * 0.85)
                        .position(x: xPos + dx, y: yPos + dy)
                }
            }
        }
    }

    private func detachedPlaqueCard(item: FallingPlaqueItem) -> some View {
        VStack(alignment: .leading, spacing: 2.5) {
            HStack(spacing: 3) {
                Text(item.dateText)
                    .font(.system(size: 8.5, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.plaqueDate)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if item.isEncrypted {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 7.5))
                        .foregroundStyle(palette.plaqueDate)
                }
            }
            Text(item.title)
                .font(.system(size: 10.5, weight: .medium, design: .serif))
                .foregroundStyle(palette.plaqueText)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .padding(.top, 8)
        .padding(.bottom, 5)
        .frame(width: 84, height: 48, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                .fill(palette.plaqueBackground)
                .shadow(color: Color.black.opacity(isDark ? 0.35 : 0.16), radius: 4, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                .strokeBorder(palette.plaqueBorder.opacity(0.85), lineWidth: 0.9)
        )
    }
}
