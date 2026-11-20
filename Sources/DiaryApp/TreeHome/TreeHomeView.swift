import AppKit
import DiaryCore
import DiaryState
import SwiftUI

struct TreeHomeView: View {
    private static let minZoom: CGFloat = 0.70
    private static let maxZoom: CGFloat = 2.60

    let workspace: DiaryWorkspace
    let weather: TreeSceneWeatherController
    let isDemo: Bool
    @Binding var newlyHungID: UUID?
    let openEntry: (UUID) -> Void
    let lockEntry: (UUID) -> Void
    let exportEntry: (UUID) -> Void
    let createEntry: () -> Void
    let openListWorkspace: () -> Void
    let openBackup: () -> Void
    let openCapabilities: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var controlActiveState

    @State private var pageIndex = 0
    @State private var selectedPeriod: String? = nil  // nil = all, "YYYY" = year, "YYYY-MM" = month
    @State private var isAppActive = true
    @State private var isWindowVisible = true
    @State private var frozenTime: Double = Date.now.timeIntervalSinceReferenceDate
    @State private var fallingPlaques: [FallingPlaqueItem] = []
    @State private var previewStageOverride: TreeGrowthStage?
    @State private var previewSeasonOverride: TreeSeason?

    // Smooth zoom & pan state for inspecting the tall tree and delicate hanging plaques.
    @State private var zoomScale: CGFloat = 1.0
    @GestureState private var pinchDelta: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @GestureState private var dragDelta: CGSize = .zero

    private var isDark: Bool { colorScheme == .dark }
    private var isFrontmost: Bool { isAppActive && controlActiveState != .inactive }

    /// Only fully pauses when Reduce Motion is enabled or the window is minimized/hidden/occluded.
    private var isAnimationPaused: Bool {
        reduceMotion || !isWindowVisible
    }

    /// Low-CPU adaptive pacing: 12 FPS calm breeze / 20 FPS rain & snow when focused; 6 FPS when visible in background.
    private var frameInterval: TimeInterval {
        if !isFrontmost { return 1.0 / 6.0 }
        switch weather.effectiveWeatherKind {
        case .rain, .thunderstorm, .snow: return 1.0 / 20.0
        default: return 1.0 / 12.0
        }
    }

    private var scopedEntries: [DiarySummary] {
        guard let selectedPeriod else { return workspace.entries }
        return workspace.entries.filter { $0.metadata.day.hasPrefix(selectedPeriod) }
    }

    private var availableYears: [String] {
        Array(Set(workspace.entries.map { String($0.metadata.day.prefix(4)) })).sorted(by: >)
    }

    private var availableMonths: [String] {
        Array(Set(workspace.entries.map { String($0.metadata.day.prefix(7)) })).sorted(by: >)
    }

    private var effectiveStage: TreeGrowthStage {
        previewStageOverride ?? TreeGrowthStage.forEntryCount(workspace.entries.count)
    }

    private var effectiveSeason: TreeSeason {
        previewSeasonOverride ?? TreeSeason.current
    }

    private var effectiveZoom: CGFloat {
        clampZoom(zoomScale * pinchDelta)
    }

    private var plaquesPerPage: Int {
        effectiveStage.primaryPlaqueCapacity
    }

    private var totalPages: Int {
        max(1, Int(ceil(Double(scopedEntries.count) / Double(plaquesPerPage))))
    }

    private var currentPageEntries: [DiarySummary] {
        let safePage = min(pageIndex, totalPages - 1)
        let start = safePage * plaquesPerPage
        guard start < scopedEntries.count else { return [] }
        let end = min(scopedEntries.count, start + plaquesPerPage)
        return Array(scopedEntries[start..<end])
    }

    /// Entries not currently on the 16 primary bough anchors — rendered via LOD in the upper canopy.
    private var distantEntries: [DiarySummary] {
        let primaryIDs = Set(currentPageEntries.map(\.id))
        return scopedEntries.filter { !primaryIDs.contains($0.id) }
    }

    var body: some View {
        let kind = weather.effectiveWeatherKind
        let stage = effectiveStage
        let season = effectiveSeason
        let timeOfDay = TreeTimeOfDay.current
        let palette = TreeAtmospherePalette.resolve(
            kind: kind, season: season, timeOfDay: timeOfDay, dark: isDark)
        let artwork = TreeArtworkCache.shared.artwork(
            for: TreeArtworkKey(weatherKind: kind, season: season, isDark: isDark, stage: stage),
            palette: palette
        )

        GeometryReader { viewport in
            let clampedOffset = clampOffset(
                CGSize(
                    width: panOffset.width + dragDelta.width,
                    height: panOffset.height + dragDelta.height
                ),
                zoom: effectiveZoom,
                in: viewport.size
            )
            let skyParallax = max(1.0, 1.0 + (effectiveZoom - 1.0) * 0.14)

            ZStack {
                // Layer 1: Zero-bitmap native SwiftUI sky & sun/moon with subtle zoom parallax.
                TreeSkyBackdropView(
                    weatherKind: kind, timeOfDay: timeOfDay, palette: palette, isDark: isDark
                )
                .scaleEffect(skyParallax)
                .ignoresSafeArea()

                // Layer 2: Zoomable & pannable hills, tree artwork, LOD distant plaques, and interactive plaques.
                GeometryReader { fullScene in
                    let layout = TreeGeometry.layout(for: fullScene.size, stage: stage)
                    let anchors = TreeGeometry.plaqueAnchors(in: fullScene.size, stage: stage)
                    let distantSlots = TreeCanopyLOD.distantSlots(
                        entries: distantEntries, in: fullScene.size, stage: stage)
                    let promoted = TreeCanopyLOD.visiblePromotedEntries(
                        from: distantSlots,
                        viewportSize: fullScene.size,
                        zoom: effectiveZoom,
                        offset: clampedOffset
                    )
                    let promotedIDs = Set(promoted.map(\.id))

                    ZStack {
                        // Static hills outside TimelineView -> zero per-frame diffing.
                        TreeHillsLayerView(layout: layout, palette: palette, isDark: isDark)

                        // Animated foliage sprites + swaying interactive plaques.
                        if isAnimationPaused {
                            animatedTreeAndPlaques(
                                time: reduceMotion ? 0 : frozenTime,
                                layout: layout,
                                anchors: anchors,
                                promoted: promoted,
                                distantSlots: distantSlots,
                                promotedIDs: promotedIDs,
                                palette: palette,
                                artwork: artwork
                            )
                        } else {
                            TimelineView(.periodic(from: .now, by: frameInterval)) { timeline in
                                animatedTreeAndPlaques(
                                    time: timeline.date.timeIntervalSinceReferenceDate,
                                    layout: layout,
                                    anchors: anchors,
                                    promoted: promoted,
                                    distantSlots: distantSlots,
                                    promotedIDs: promotedIDs,
                                    palette: palette,
                                    artwork: artwork
                                )
                            }
                        }
                    }
                }
                .scaleEffect(effectiveZoom)
                .offset(clampedOffset)
                .ignoresSafeArea()

                // Layer 3: Full-bleed lightweight 8-bit weather particles & clouds.
                Group {
                    if isAnimationPaused {
                        TreeWeatherOverlayView(
                            weatherKind: kind,
                            windSpeedKmh: weather.effectiveWindSpeedKmh,
                            palette: palette,
                            time: reduceMotion ? 0 : frozenTime,
                            isDark: isDark
                        )
                    } else {
                        TimelineView(.periodic(from: .now, by: frameInterval)) { timeline in
                            TreeWeatherOverlayView(
                                weatherKind: kind,
                                windSpeedKmh: weather.effectiveWindSpeedKmh,
                                palette: palette,
                                time: timeline.date.timeIntervalSinceReferenceDate,
                                isDark: isDark
                            )
                        }
                    }
                }
                .allowsHitTesting(false)
                .ignoresSafeArea()

                // Decoupled 60 FPS sibling overlay so falling plaques never drop frames.
                if !fallingPlaques.isEmpty {
                    FallingPlaqueOverlayView(
                        items: fallingPlaques,
                        palette: palette,
                        isDark: isDark
                    ) { finishedID in
                        fallingPlaques.removeAll { $0.id == finishedID }
                    }
                    .scaleEffect(effectiveZoom)
                    .offset(clampedOffset)
                    .ignoresSafeArea()
                }

                // Layer 4: Minimal floating HUD + Year/Month Switcher + Zoom Controls.
                VStack(spacing: 0) {
                    topBar(stage: stage)
                    if let status = weather.statusMessage {
                        HStack {
                            Spacer()
                            Text(status)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 6)
                    }
                    Spacer()
                    if workspace.isLoading {
                        ProgressView("正在打开日记库…")
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial, in: Capsule())
                        Spacer()
                    }
                    bottomBar(viewportSize: viewport.size, stage: stage)
                }
            }
            .contentShape(Rectangle())
            .gesture(zoomGesture(in: viewport.size))
            .simultaneousGesture(panGesture(in: viewport.size))
            .onTapGesture(count: 2) {
                toggleQuickZoom()
            }
        }
        .background(WindowVisibilityObserver(isVisible: $isWindowVisible).frame(width: 0, height: 0))
        .onAppear {
            weather.refreshIfAuthorized()
            if newlyHungID != nil {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(1900))
                    newlyHungID = nil
                }
            }
        }
        .onChange(of: scopedEntries.count) { _, _ in
            if pageIndex >= totalPages { pageIndex = max(0, totalPages - 1) }
        }
        .onChange(of: selectedPeriod) { _, _ in
            pageIndex = 0
        }
        .onChange(of: isWindowVisible) { _, visible in
            if !visible { frozenTime = Date.now.timeIntervalSinceReferenceDate }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) {
            _ in
            isAppActive = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) {
            _ in
            isAppActive = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didHideNotification)) {
            _ in
            frozenTime = Date.now.timeIntervalSinceReferenceDate
            isWindowVisible = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didUnhideNotification)) {
            _ in
            isWindowVisible = true
        }
    }

    @ViewBuilder
    private func animatedTreeAndPlaques(
        time: Double,
        layout: TreeGeometry.Layout,
        anchors: [PlaqueAnchor],
        promoted: [DistantPlaqueEntry],
        distantSlots: [DistantPlaqueEntry],
        promotedIDs: Set<UUID>,
        palette: TreeAtmospherePalette,
        artwork: TreeArtworkSet
    ) -> some View {
        ZStack {
            TreeArtworkLayersView(
                artwork: artwork,
                layout: layout,
                windSpeedKmh: weather.effectiveWindSpeedKmh,
                time: time,
                reduceMotion: reduceMotion
            )

            // Distant LOD miniature plaques rendered in one fast Canvas pass for 100–1,000+ diaries.
            if !workspace.isLoading && !distantSlots.isEmpty {
                DistantPlaquesCanvasView(
                    slots: distantSlots,
                    excludedIDs: promotedIDs,
                    palette: palette,
                    isDark: isDark
                )
            }

            if !workspace.isLoading {
                if currentPageEntries.isEmpty {
                    let emptySway =
                        reduceMotion
                        ? 0.0
                        : TreeGeometry.plaqueSwayDegrees(
                            time: time,
                            windSpeedKmh: weather.effectiveWindSpeedKmh,
                            phase: anchors[1].phase
                        )
                    EmptyTreePlaqueView(
                        anchor: anchors[1],
                        palette: palette,
                        swayDegrees: emptySway,
                        isDark: isDark,
                        action: createEntry
                    )
                } else {
                    // Primary bough interactive plaques (up to 16)
                    ForEach(Array(currentPageEntries.enumerated()), id: \.element.id) { idx, entry in
                        let anchor = anchors[idx % anchors.count]
                        interactivePlaque(
                            entry: entry, anchor: anchor, time: time,
                            groundY: layout.origin.y + 4 * layout.scale, palette: palette)
                    }

                    // Promoted close-up canopy plaques when zoomed in (>= 1.40x)
                    ForEach(promoted) { item in
                        interactivePlaque(
                            entry: item.entry, anchor: item.anchor, time: time,
                            groundY: layout.origin.y + 4 * layout.scale, palette: palette)
                    }
                }
            }
        }
    }

    private func interactivePlaque(
        entry: DiarySummary,
        anchor: PlaqueAnchor,
        time: Double,
        groundY: CGFloat,
        palette: TreeAtmospherePalette
    ) -> some View {
        let sway =
            reduceMotion
            ? 0.0
            : TreeGeometry.plaqueSwayDegrees(
                time: time,
                windSpeedKmh: weather.effectiveWindSpeedKmh,
                phase: anchor.phase
            )
        return DiaryPlaqueView(
            entry: entry,
            anchor: anchor,
            palette: palette,
            swayDegrees: sway,
            isNewlyHung: newlyHungID == entry.id,
            isDark: isDark,
            onOpen: { openEntry(entry.id) },
            onLockAction: { lockEntry(entry.id) },
            onExport: { exportEntry(entry.id) },
            onTrash: {
                trashFromTree(entry: entry, anchor: anchor, groundY: groundY)
            }
        )
    }

    private func trashFromTree(entry: DiarySummary, anchor: PlaqueAnchor, groundY: CGFloat) {
        Task {
            if workspace.isShowingTrash {
                await workspace.showTrash(false)
            }
            if workspace.selectedID != entry.id {
                await workspace.select(entry.id)
            }
            guard workspace.selectedID == entry.id else { return }
            await workspace.trashSelected()
            guard !workspace.entries.contains(where: { $0.id == entry.id }), !reduceMotion else {
                return
            }
            let startPoint = CGPoint(
                x: anchor.branchPoint.x,
                y: anchor.branchPoint.y + anchor.cordLength + 24
            )
            fallingPlaques.append(
                FallingPlaqueItem(
                    id: entry.id,
                    title: DiaryPlaqueView.displayTitle(for: entry.metadata.title),
                    dateText: DiaryPlaqueView.shortDateText(for: entry.metadata.day),
                    isEncrypted: entry.isEncrypted,
                    startPoint: startPoint,
                    groundY: groundY,
                    startedAt: .now,
                    windSpeedKmh: weather.effectiveWindSpeedKmh
                ))
        }
    }

    // MARK: - Zoom & Pan Gestures

    private func clampZoom(_ value: CGFloat) -> CGFloat {
        min(Self.maxZoom, max(Self.minZoom, value))
    }

    private func clampOffset(_ proposed: CGSize, zoom: CGFloat, in size: CGSize) -> CGSize {
        guard zoom > 1.01 else { return .zero }
        let maxX = size.width * (zoom - 1.0) * 0.52
        let maxY = size.height * (zoom - 1.0) * 0.52
        return CGSize(
            width: min(maxX, max(-maxX, proposed.width)),
            height: min(maxY, max(-maxY, proposed.height))
        )
    }

    private func zoomGesture(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .updating($pinchDelta) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                let next = clampZoom(zoomScale * value.magnification)
                zoomScale = next
                panOffset = clampOffset(panOffset, zoom: next, in: size)
            }
    }

    private func panGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .updating($dragDelta) { value, state, _ in
                guard effectiveZoom > 1.01 else { return }
                state = value.translation
            }
            .onEnded { value in
                guard zoomScale > 1.01 else { return }
                let combined = CGSize(
                    width: panOffset.width + value.translation.width,
                    height: panOffset.height + value.translation.height
                )
                panOffset = clampOffset(combined, zoom: zoomScale, in: size)
            }
    }

    private func stepZoom(by delta: CGFloat, in size: CGSize) {
        withAnimation(.easeOut(duration: 0.2)) {
            let next = clampZoom(zoomScale + delta)
            zoomScale = next
            panOffset = clampOffset(panOffset, zoom: next, in: size)
        }
    }

    private func resetZoom() {
        withAnimation(.easeOut(duration: 0.22)) {
            zoomScale = 1.0
            panOffset = .zero
        }
    }

    private func toggleQuickZoom() {
        withAnimation(.easeInOut(duration: 0.24)) {
            if abs(zoomScale - 1.0) > 0.08 {
                zoomScale = 1.0
                panOffset = .zero
            } else {
                zoomScale = 1.65
            }
        }
    }

    // MARK: - HUD

    private func topBar(stage: TreeGrowthStage) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("栖木")
                        .font(.system(size: 20, weight: .semibold, design: .serif))
                    if isDemo {
                        Text("示例库")
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }
                Text("把一天，挂在风里")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            weatherAndStageMenu(stage: stage)

            Button(action: createEntry) {
                Label("写一篇", systemImage: "square.and.pencil")
                    .font(.system(size: 12.5, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(DiaryStyle.accent, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .help("新建日记 (⌘N)")
            .disabled(workspace.isBusy)

            Button(action: openListWorkspace) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 30, height: 30)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .help("列表、搜索与废纸篓")
            .disabled(workspace.isBusy)

            Button(action: openBackup) {
                Image(systemName: "externaldrive")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 30, height: 30)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .help("备份与恢复")
            .disabled(workspace.isBusy)

            Button(action: openCapabilities) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 30, height: 30)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .help("技术验证：Touch ID")
            .disabled(workspace.isBusy)
        }
        .padding(.leading, 84)
        .padding(.trailing, 24)
        .padding(.top, 16)
    }

    private func weatherAndStageMenu(stage: TreeGrowthStage) -> some View {
        Menu {
            Button {
                weather.refreshLiveWeather()
            } label: {
                Label("同步当前位置天气", systemImage: "location")
            }
            .disabled(weather.isLoading)

            if let live = weather.liveWeather {
                Text("实时：\(live.summaryText)（\(live.source)）")
            }

            Divider()

            Button {
                weather.previewOverride = nil
            } label: {
                if weather.previewOverride == nil {
                    Label("使用实时天气", systemImage: "checkmark")
                } else {
                    Text("使用实时天气")
                }
            }

            ForEach(TreeWeatherKind.allCases) { kind in
                Button {
                    weather.previewOverride = kind
                } label: {
                    if weather.previewOverride == kind {
                        Label("天气预览：\(kind.label)", systemImage: "checkmark")
                    } else {
                        Label("天气预览：\(kind.label)", systemImage: kind.symbolName)
                    }
                }
            }

            Divider()

            Menu("季节色板（当前：\(effectiveSeason.shortLabel)）") {
                Button {
                    previewSeasonOverride = nil
                } label: {
                    if previewSeasonOverride == nil {
                        Label("随当前月份自动切换", systemImage: "checkmark")
                    } else {
                        Text("随当前月份自动切换")
                    }
                }
                Divider()
                ForEach(TreeSeason.allCases) { candidate in
                    Button {
                        previewSeasonOverride = candidate
                    } label: {
                        if previewSeasonOverride == candidate {
                            Label(candidate.label, systemImage: "checkmark")
                        } else {
                            Text(candidate.label)
                        }
                    }
                }
            }

            Menu("树龄成长（当前：\(stage.label)）") {
                Button {
                    previewStageOverride = nil
                } label: {
                    if previewStageOverride == nil {
                        Label("随日记篇数自动生长", systemImage: "checkmark")
                    } else {
                        Text("随日记篇数自动生长")
                    }
                }
                Divider()
                ForEach(TreeGrowthStage.allCases) { candidate in
                    Button {
                        previewStageOverride = candidate
                    } label: {
                        let title = "\(candidate.label)（\(candidate.rangeHint)）"
                        if previewStageOverride == candidate {
                            Label(title, systemImage: "checkmark")
                        } else {
                            Text(title)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                if weather.isLoading {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: weather.effectiveWeatherKind.symbolName)
                        .font(.system(size: 12))
                }
                Text(weather.pillLabel)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("同步当天位置天气、切换天气场景或预览树龄成长")
    }

    private func periodDisplayLabel(_ period: String?) -> String {
        guard let period else { return "全部时光" }
        if period.count == 4 { return "\(period) 年" }
        let parts = period.split(separator: "-")
        if parts.count == 2, let m = Int(parts[1]) {
            return "\(parts[0]) 年 \(m) 月"
        }
        return period
    }

    private var periodSwitcherMenu: some View {
        Menu {
            Button {
                selectedPeriod = nil
            } label: {
                if selectedPeriod == nil {
                    Label("全部时光（\(workspace.entries.count) 篇）", systemImage: "checkmark")
                } else {
                    Text("全部时光（\(workspace.entries.count) 篇）")
                }
            }

            if availableYears.count > 1 {
                Divider()
                ForEach(availableYears, id: \.self) { year in
                    Button {
                        selectedPeriod = year
                    } label: {
                        if selectedPeriod == year {
                            Label("\(year) 年", systemImage: "checkmark")
                        } else {
                            Text("\(year) 年")
                        }
                    }
                }
            }

            if !availableMonths.isEmpty {
                Divider()
                ForEach(availableMonths.prefix(12), id: \.self) { month in
                    Button {
                        selectedPeriod = month
                    } label: {
                        let label = periodDisplayLabel(month)
                        if selectedPeriod == month {
                            Label(label, systemImage: "checkmark")
                        } else {
                            Text(label)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .font(.system(size: 10.5))
                Text(periodDisplayLabel(selectedPeriod))
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.primary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("按年份或月份筛选树上的日记")
    }

    private func bottomBar(viewportSize: CGSize, stage: TreeGrowthStage) -> some View {
        ZStack {
            HStack(spacing: 10) {
                if !workspace.entries.isEmpty {
                    periodSwitcherMenu
                    Divider().frame(height: 11)
                }

                if scopedEntries.count > plaquesPerPage {
                    Button {
                        pageIndex = max(0, pageIndex - 1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .disabled(pageIndex <= 0)

                    Text("\(stage.label) · 第 \(pageIndex + 1)/\(totalPages) 组 · 共 \(scopedEntries.count) 篇")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    Button {
                        pageIndex = min(totalPages - 1, pageIndex + 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .disabled(pageIndex >= totalPages - 1)

                    Divider().frame(height: 11)

                    Button("全部列表", action: openListWorkspace)
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DiaryStyle.accent)
                } else {
                    let stagePrefix = previewStageOverride == nil ? stage.label : "预览：\(stage.label)"
                    Text(
                        scopedEntries.isEmpty
                            ? "\(stagePrefix) · 等待第一篇日记"
                            : "\(stagePrefix) · 挂着 \(scopedEntries.count) 篇日记"
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())

            HStack {
                Spacer()
                HStack(spacing: 8) {
                    Button {
                        stepZoom(by: -0.25, in: viewportSize)
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("-", modifiers: .command)
                    .disabled(effectiveZoom <= Self.minZoom + 0.01)
                    .help("缩小 (⌘-)")

                    Button {
                        resetZoom()
                    } label: {
                        Text("\(Int((effectiveZoom * 100).rounded()))%")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .frame(minWidth: 38)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("0", modifiers: .command)
                    .help("还原缩放 (⌘0)")

                    Button {
                        stepZoom(by: 0.25, in: viewportSize)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("=", modifiers: .command)
                    .disabled(effectiveZoom >= Self.maxZoom - 0.01)
                    .help("放大 (⌘+)")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .padding(.horizontal, 24)
        }
        .padding(.bottom, 16)
    }
}
