import DiaryCore
import SwiftUI

struct DiaryPlaqueView: View {
    let entry: DiarySummary
    let anchor: PlaqueAnchor
    let palette: TreeAtmospherePalette
    let swayDegrees: Double
    let isNewlyHung: Bool
    let isDark: Bool
    let onOpen: () -> Void
    let onLockAction: () -> Void
    let onExport: () -> Void
    let onTrash: () -> Void

    @State private var isHovered = false
    @State private var hoverNudge: Double = 0
    @State private var hangProgress: CGFloat = 1.0
    @State private var newGlowOpacity: Double = 0

    private var plaqueWidth: CGFloat { 84 }
    private var plaqueHeight: CGFloat { 48 }

    var body: some View {
        Button(action: onOpen) {
            VStack(spacing: 0) {
                Circle()
                    .fill(palette.trunkDark)
                    .frame(width: 4.5, height: 4.5)

                Rectangle()
                    .fill(palette.plaqueBorder.opacity(0.90))
                    .frame(width: 1.0, height: anchor.cordLength)

                VStack(alignment: .leading, spacing: 2.5) {
                    HStack(spacing: 3) {
                        Text(Self.shortDateText(for: entry.metadata.day))
                            .font(.system(size: 8.5, weight: .medium, design: .rounded))
                            .foregroundStyle(palette.plaqueDate)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if entry.isEncrypted {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 7.5))
                                .foregroundStyle(palette.plaqueDate)
                        }
                    }

                    Text(Self.displayTitle(for: entry.metadata.title))
                        .font(.system(size: 10.5, weight: .medium, design: .serif))
                        .foregroundStyle(palette.plaqueText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 7)
                .padding(.top, 8)
                .padding(.bottom, 5)
                .frame(width: plaqueWidth, height: plaqueHeight, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                        .fill(palette.plaqueBackground)
                        .shadow(
                            color: newGlowOpacity > 0.01
                                ? DiaryStyle.accent.opacity(newGlowOpacity * 0.65)
                                : Color.black.opacity(
                                    isHovered ? (isDark ? 0.48 : 0.24) : (isDark ? 0.30 : 0.14)),
                            radius: newGlowOpacity > 0.01 ? 12 : (isHovered ? 8 : 4),
                            x: 0,
                            y: isHovered ? 4 : 2.5
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                        .strokeBorder(
                            isHovered || newGlowOpacity > 0.1
                                ? DiaryStyle.accent : palette.plaqueBorder.opacity(0.85),
                            lineWidth: isHovered || newGlowOpacity > 0.1 ? 1.4 : 0.9
                        )
                )
                .overlay(alignment: .top) {
                    Circle()
                        .fill(palette.skyMid)
                        .frame(width: 4, height: 4)
                        .overlay(Circle().stroke(palette.plaqueBorder, lineWidth: 0.85))
                        .offset(y: 2.5)
                }
            }
            .scaleEffect(isHovered ? 1.16 : (0.88 + 0.12 * hangProgress), anchor: .top)
            .rotationEffect(
                .degrees((isHovered ? hoverNudge : swayDegrees) + Double(1.0 - hangProgress) * -14),
                anchor: .top
            )
            .offset(y: (1.0 - hangProgress) * -18)
            .opacity(Double(hangProgress))
            .animation(.easeOut(duration: 0.16), value: isHovered)
            .animation(.interpolatingSpring(stiffness: 160, damping: 11), value: hoverNudge)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .zIndex(isHovered ? 10 : (isNewlyHung ? 5 : 0))
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                // Brief tactile wind-chime nudge when cursor brushes the wooden plaque.
                hoverNudge = swayDegrees >= 0 ? 4.5 : -4.5
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(130))
                    hoverNudge = 0
                }
            } else {
                hoverNudge = 0
            }
        }
        .onAppear {
            if isNewlyHung {
                hangProgress = 0
                newGlowOpacity = 1.0
                withAnimation(.spring(response: 0.58, dampingFraction: 0.62)) {
                    hangProgress = 1.0
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(1100))
                    withAnimation(.easeOut(duration: 0.65)) {
                        newGlowOpacity = 0
                    }
                }
            }
        }
        .contextMenu {
            Button {
                onOpen()
            } label: {
                Label(L10n.tr("打开日记", "Open Entry"), systemImage: "book.pages")
            }

            Button {
                onLockAction()
            } label: {
                Label(
                    entry.isEncrypted
                        ? L10n.tr("解锁日记…", "Unlock Entry…")
                        : L10n.tr("加密这篇日记…", "Encrypt Entry…"),
                    systemImage: entry.isEncrypted ? "lock.open" : "lock"
                )
            }

            if entry.isEncrypted {
                Button {
                } label: {
                    Label(
                        L10n.tr("导出 Markdown（需先解锁）", "Export Markdown (Unlock First)"),
                        systemImage: "square.and.arrow.up"
                    )
                }
                .disabled(true)
            } else {
                Button {
                    onExport()
                } label: {
                    Label(L10n.tr("导出 Markdown…", "Export Markdown…"), systemImage: "square.and.arrow.up")
                }
            }

            Divider()

            Button(role: .destructive) {
                onTrash()
            } label: {
                Label(L10n.tr("移入废纸篓", "Move to Trash"), systemImage: "trash")
            }
        }
        .help(
            "\(Self.shortDateText(for: entry.metadata.day)) · \(Self.displayTitle(for: entry.metadata.title))"
        )
        .position(
            x: anchor.branchPoint.x,
            y: anchor.branchPoint.y + (anchor.cordLength + plaqueHeight + 4.5) * 0.5 - 2.25
        )
        .accessibilityLabel(accessibilityTitle)
        .accessibilityHint(
            L10n.tr(
                "点击打开这篇日记，右键可加密、导出或移入废纸篓",
                "Click to open this entry; right-click to encrypt, export, or move to Trash"
            )
        )
    }

    static func displayTitle(for title: String) -> String {
        title.isEmpty ? L10n.tr("无标题日记", "Untitled Entry") : title
    }

    static func shortDateText(for day: String) -> String {
        let today = DiaryMetadata(title: "").day
        if day == today { return L10n.tr("今天", "Today") }
        let parts = day.split(separator: "-")
        guard parts.count == 3, let month = Int(parts[1]), let date = Int(parts[2]) else {
            return day
        }
        let currentYear = today.prefix(4)
        if parts[0] == currentYear {
            return "\(month).\(date)"
        }
        return "\(parts[0]).\(month).\(date)"
    }

    private var accessibilityTitle: String {
        let privacy = entry.isEncrypted ? L10n.tr("私密日记，", "Private entry, ") : ""
        return
            "\(privacy)\(Self.shortDateText(for: entry.metadata.day)), \(Self.displayTitle(for: entry.metadata.title))"
    }
}

struct EmptyTreePlaqueView: View {
    let anchor: PlaqueAnchor
    let palette: TreeAtmospherePalette
    let swayDegrees: Double
    let isDark: Bool
    let action: () -> Void

    @State private var isHovered = false

    private var plaqueWidth: CGFloat { 104 }
    private var plaqueHeight: CGFloat { 56 }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Circle()
                    .fill(palette.trunkDark)
                    .frame(width: 4.5, height: 4.5)

                Rectangle()
                    .fill(palette.plaqueBorder.opacity(0.85))
                    .frame(width: 1.0, height: anchor.cordLength)

                VStack(spacing: 4) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 13, weight: .light))
                        .foregroundStyle(DiaryStyle.accent)
                    Text(L10n.tr("挂上第一篇", "Hang First Entry"))
                        .font(.system(size: 10.5, weight: .medium, design: .serif))
                        .foregroundStyle(palette.plaqueText)
                }
                .frame(width: plaqueWidth, height: plaqueHeight)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(palette.plaqueBackground.opacity(0.92))
                        .shadow(
                            color: Color.black.opacity(isDark ? 0.30 : 0.14),
                            radius: isHovered ? 8 : 4,
                            x: 0, y: 3
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(
                            isHovered ? DiaryStyle.accent : palette.plaqueBorder,
                            style: StrokeStyle(lineWidth: 1.1, dash: [3.5, 2.5])
                        )
                )
            }
            .scaleEffect(isHovered ? 1.12 : 1.0, anchor: .top)
            .rotationEffect(.degrees(isHovered ? 0 : swayDegrees), anchor: .top)
            .animation(.easeOut(duration: 0.16), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .position(
            x: anchor.branchPoint.x,
            y: anchor.branchPoint.y + (anchor.cordLength + plaqueHeight + 4.5) * 0.5 - 2.25
        )
        .accessibilityLabel(L10n.tr("挂上第一篇日记", "Hang your first diary entry"))
    }
}
