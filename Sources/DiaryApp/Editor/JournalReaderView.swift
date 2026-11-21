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
                    Button(L10n.tr("重试保存", "Retry Save")) { Task { await workspace.flush() } }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                Divider().opacity(0.4)
            }

            if !workspace.loadIssues.isEmpty {
                Text(
                    L10n.tr(
                        "有 \(workspace.loadIssues.count) 个文件未载入，原文件已保留。",
                        "\(workspace.loadIssues.count) file(s) could not be loaded; originals were preserved."
                    )
                )
                .font(.system(size: 12))
                .foregroundStyle(.orange)
                .padding(.vertical, 10)
            }

            if workspace.isLoading {
                ProgressView(L10n.tr("正在打开日记库…", "Opening library…"))
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
                    Text(L10n.tr("给今天留下一点记录", "Leave a quiet note for today"))
                        .font(.system(size: 22, design: .serif))
                    Button(L10n.tr("写下第一篇日记", "Write First Entry")) {
                        Task { await workspace.addEntry() }
                    }
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
                    Text(L10n.tr("日记树", "Tree"))
                        .font(.system(size: 12.5, weight: .medium))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .help(L10n.tr("保存并返回日记树主页", "Save and return to Diary Tree"))
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
            .help(L10n.tr("展开或收起目录、搜索与废纸篓", "Toggle Entries, Search & Trash Drawer"))
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
            .help(L10n.tr("新建日记 (⌘N)", "New Entry (⌘N)"))
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
                .help(
                    workspace.isLocked
                        ? L10n.tr("解锁日记", "Unlock Entry")
                        : L10n.tr("加密或锁定日记", "Encrypt or Lock Entry")
                )
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
            .help(L10n.tr("备份与恢复", "Backup & Restore"))
            .disabled(workspace.isBusy)

            Button(action: openCapabilities) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 30, height: 30)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .help(L10n.tr("技术验证：Touch ID", "Diagnostics: Touch ID"))
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
                    Button(L10n.tr("停用这篇日记的 Touch ID", "Disable Touch ID for Entry")) {
                        Task { await session.disableTouchID() }
                    }
                } else {
                    Button(L10n.tr("为这篇日记启用 Touch ID", "Enable Touch ID for Entry")) {
                        Task { await session.enableTouchID() }
                    }
                    .disabled(session.isLocked || session.biometricUnavailableReason != nil)
                    Text(
                        session.biometricUnavailableReason
                            ?? L10n.tr("先用密码解锁，再启用 Touch ID", "Unlock with password first to enable Touch ID")
                    )
                }
                Divider()
            }
            if workspace.location != nil {
                Button(L10n.tr("清除位置", "Clear Location")) { _ = workspace.clearLocation() }
            }
            Button(L10n.tr("获取当前位置…", "Use Current Location…")) {
                Task { await workspace.attachCurrentLocation() }
            }
            .disabled(workspace.isLocked || workspace.isBusy)
            Button(L10n.tr("在地图上选点…", "Pick Location on Map…"), action: openMapPicker)
                .disabled(workspace.isLocked || workspace.isBusy)
            Button(L10n.tr("刷新天气", "Refresh Weather")) { workspace.refreshWeather() }
                .disabled(
                    workspace.isLocked || workspace.isBusy || workspace.location == nil
                        || !workspace.canRefreshWeather || workspace.isWeatherLoading)
            if workspace.location != nil && !workspace.canRefreshWeather {
                Text(L10n.tr("过去日期的日记不获取当前天气", "Current weather is not fetched for past entries"))
            }
            if workspace.isLocked { Text(L10n.tr("解锁后可添加位置", "Unlock to attach location")) }
            Divider()
            Button(L10n.tr("导出 Markdown…", "Export Markdown…")) {
                MarkdownExportPanel.present(
                    for: workspace,
                    initialDirectory: configuration.isValidation
                        ? configuration.libraryURL.deletingLastPathComponent() : nil)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(workspace.isLocked)
            if workspace.isLocked { Text(L10n.tr("解锁后可导出正文", "Unlock to export entry")) }
            Divider()
            Button(L10n.tr("移入废纸篓", "Move to Trash"), systemImage: "trash") {
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
        .help(L10n.tr("日记操作", "Entry Actions"))
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
                .help(L10n.tr("收起目录", "Close Drawer"))
            }
            .ignoresSafeArea(edges: .bottom)
            .transition(.move(edge: .leading))
        }
    }
}
