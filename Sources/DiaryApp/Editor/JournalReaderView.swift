import DiaryState
import SwiftUI

/// Immersive paper-sheet reading & writing scene resting over a static, softly blurred tree backdrop.
struct JournalReaderView: View {
    let workspace: DiaryWorkspace
    let configuration: AppConfiguration
    let weather: TreeSceneWeatherController
    @Binding var showsDrawer: Bool
    let returnToTree: () -> Void
    let openPassword: () -> Void
    let openMapPicker: () -> Void
    let openBackup: () -> Void
    let openCapabilities: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        let kind = weather.effectiveWeatherKind
        let stage = TreeGrowthStage.forEntryCount(workspace.entries.count)
        let season = TreeSeason.current
        let timeOfDay = TreeTimeOfDay.current
        let palette = TreeAtmospherePalette.resolve(
            kind: kind, season: season, timeOfDay: timeOfDay, dark: isDark)
        let artwork = TreeArtworkCache.shared.artwork(
            for: TreeArtworkKey(weatherKind: kind, season: season, isDark: isDark, stage: stage),
            palette: palette
        )

        ZStack {
            // Static blurred tree atmosphere reusing cached sprites — zero TimelineView, low RAM.
            GeometryReader { proxy in
                let layout = TreeGeometry.layout(for: proxy.size, stage: stage)
                ZStack {
                    TreeSkyBackdropView(
                        weatherKind: kind, timeOfDay: timeOfDay, palette: palette, isDark: isDark)
                    TreeHillsLayerView(layout: layout, palette: palette, isDark: isDark)
                    TreeArtworkLayersView(
                        artwork: artwork,
                        layout: layout,
                        windSpeedKmh: 0,
                        time: 0,
                        reduceMotion: true
                    )
                }
            }
            .scaleEffect(1.06)
            .blur(radius: 14)
            .overlay(isDark ? Color.black.opacity(0.38) : Color.white.opacity(0.28))
            .ignoresSafeArea()

            VStack(spacing: 0) {
                floatingTopBar
                paperSheet
                    .padding(.horizontal, 28)
                    .padding(.top, 6)
                    .padding(.bottom, 22)
            }

            if showsDrawer {
                drawerOverlay
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.20), value: showsDrawer)
    }

    // MARK: - Centered Letter Paper Sheet

    private var paperSheet: some View {
        let identity = workspace.editorIdentity
        return VStack(spacing: 0) {
            if let failure = workspace.session?.autosave.status.failure {
                HStack {
                    Text(failure).font(.system(size: 12)).foregroundStyle(.red)
                    Spacer()
                    Button("重试保存") { Task { await workspace.flush() } }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                Divider().opacity(0.4)
            }

            if !workspace.loadIssues.isEmpty {
                Text("有 \(workspace.loadIssues.count) 个文件未载入，原文件已保留。")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .padding(.vertical, 10)
            }

            if workspace.isLoading {
                ProgressView("正在打开日记库…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if workspace.isShowingTrash {
                TrashDetailView(workspace: workspace)
            } else if workspace.isLocked {
                LockedDiaryView(
                    unlock: openPassword,
                    touchID: workspace.session?.isBiometricEnabled == true
                        ? {
                            if let identity {
                                Task { await workspace.unlockWithTouchID(from: identity) }
                            }
                        } : nil,
                    isBusy: workspace.isBusy,
                    unavailableReason: workspace.session?.biometricUnavailableReason
                )
            } else if workspace.selectedEntry != nil {
                DiaryEditorView(workspace: workspace, openMapPicker: openMapPicker)
                    .id(workspace.editorIdentity)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "leaf")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(DiaryStyle.accent)
                    Text("给今天留下一点记录")
                        .font(.system(size: 22, design: .serif))
                    Button("写下第一篇日记") { Task { await workspace.addEntry() } }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: 760, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(DiaryStyle.page)
                .shadow(
                    color: Color.black.opacity(isDark ? 0.42 : 0.14),
                    radius: 26,
                    x: 0,
                    y: 12
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(DiaryStyle.paperBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Minimal Floating Top Bar

    private var floatingTopBar: some View {
        HStack(spacing: 10) {
            Button(action: returnToTree) {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Image(systemName: "tree")
                        .font(.system(size: 12))
                        .foregroundStyle(DiaryStyle.accent)
                    Text("日记树")
                        .font(.system(size: 12.5, weight: .medium))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .help("保存并返回日记树主页")
            .disabled(workspace.isBusy)

            Button {
                showsDrawer.toggle()
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(showsDrawer ? DiaryStyle.accent : .primary)
                    .frame(width: 30, height: 30)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .help("展开或收起目录、搜索与废纸篓")
            .disabled(workspace.isBusy)

            Spacer()

            Button {
                Task { await workspace.addEntry() }
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 30, height: 30)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .help("新建日记 (⌘N)")
            .disabled(workspace.isBusy)

            if workspace.selectedEntry != nil {
                Button {
                    if workspace.selectedEntry?.content.isEncrypted == true && !workspace.isLocked {
                        workspace.lockSelected()
                    } else {
                        openPassword()
                    }
                } label: {
                    Image(systemName: workspace.isLocked ? "lock.fill" : "lock")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(workspace.isLocked ? DiaryStyle.accent : .primary)
                        .frame(width: 30, height: 30)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .help(workspace.isLocked ? "解锁日记" : "加密或锁定日记")
                .disabled(workspace.isBusy)

                diaryActionsMenu
            }

            Button(action: openBackup) {
                Image(systemName: "externaldrive")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 30, height: 30)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .help("备份与恢复")
            .disabled(workspace.isBusy)

            Button(action: openCapabilities) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 30, height: 30)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .help("技术验证：Touch ID")
            .disabled(workspace.isBusy)
        }
        .padding(.leading, 84)
        .padding(.trailing, 24)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var diaryActionsMenu: some View {
        Menu {
            if let session = workspace.session, session.document.content.isEncrypted {
                if session.isBiometricEnabled {
                    Button("停用这篇日记的 Touch ID") { Task { await session.disableTouchID() } }
                } else {
                    Button("为这篇日记启用 Touch ID") { Task { await session.enableTouchID() } }
                        .disabled(session.isLocked || session.biometricUnavailableReason != nil)
                    Text(session.biometricUnavailableReason ?? "先用密码解锁，再启用 Touch ID")
                }
                Divider()
            }
            if workspace.location != nil {
                Button("清除位置") { _ = workspace.clearLocation() }
            }
            Button("获取当前位置…") {
                Task { await workspace.attachCurrentLocation() }
            }
            .disabled(workspace.isLocked || workspace.isBusy)
            Button("在地图上选点…", action: openMapPicker)
                .disabled(workspace.isLocked || workspace.isBusy)
            Button("刷新天气") { workspace.refreshWeather() }
                .disabled(
                    workspace.isLocked || workspace.isBusy || workspace.location == nil
                        || !workspace.canRefreshWeather || workspace.isWeatherLoading)
            if workspace.location != nil && !workspace.canRefreshWeather {
                Text("过去日期的日记不获取当前天气")
            }
            if workspace.isLocked { Text("解锁后可添加位置") }
            Divider()
            Button("导出 Markdown…") {
                MarkdownExportPanel.present(
                    for: workspace,
                    initialDirectory: configuration.isValidation
                        ? configuration.libraryURL.deletingLastPathComponent() : nil)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(workspace.isLocked)
            if workspace.isLocked { Text("解锁后可导出正文") }
            Divider()
            Button("移入废纸篓", systemImage: "trash") {
                Task { await workspace.trashSelected() }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 30, height: 30)
                .background(.ultraThinMaterial, in: Circle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("日记操作")
        .disabled(workspace.isBusy)
    }

    // MARK: - Slide-Over Translucent Directory Drawer

    private var drawerOverlay: some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(isDark ? 0.34 : 0.14)
                .ignoresSafeArea()
                .onTapGesture { showsDrawer = false }

            ZStack(alignment: .topTrailing) {
                DiarySidebar(workspace: workspace, isDemo: configuration.isDemo)
                    .frame(width: 280)
                    .background(.regularMaterial)
                    .overlay(alignment: .trailing) {
                        Rectangle()
                            .fill(DiaryStyle.paperBorder)
                            .frame(width: 1)
                    }
                    .shadow(color: Color.black.opacity(isDark ? 0.45 : 0.18), radius: 20, x: 6, y: 0)

                Button {
                    showsDrawer = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(.top, 14)
                .padding(.trailing, 14)
                .help("收起目录")
            }
            .ignoresSafeArea(edges: .bottom)
            .transition(.move(edge: .leading))
        }
    }
}
