import AppKit
import DiaryCore
import SwiftUI

struct BackupView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var controller: BackupController
    @ViewState<PendingRestore?> private var pendingRestore: PendingRestore?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("备份与恢复").font(.system(size: 22, weight: .medium, design: .serif))
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("快照只复制日记文件与清单校验值，清单不含标题或正文。私密日记保持密文原样复制。")
                .font(.system(size: 11)).foregroundStyle(.secondary)

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Label("本地备份目录", systemImage: "folder.badge.gearshape").font(.headline)
                    if controller.hasDirectory, let name = controller.directoryName {
                        HStack(spacing: 8) {
                            Text("已授权：\(name)").font(.system(size: 12, weight: .medium))
                            Spacer()
                            if let latest = controller.latestSnapshot {
                                Text(
                                    "最近：\(latest.manifest.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(formattedBytes(latest.manifest.totalBytes))"
                                )
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text("尚未选择备份目录。可选择本机文件夹或外置硬盘目录，创建不可变快照。")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button(controller.hasDirectory ? "重新选择目录…" : "选择备份目录…") {
                            chooseBackupDirectory()
                        }
                        if controller.hasDirectory {
                            Button("立即创建快照") { controller.createSnapshot() }
                                .buttonStyle(.borderedProminent)
                                .disabled(controller.isBusy)
                            Button {
                                controller.openBackupDirectoryInFinder()
                            } label: {
                                Label("在 Finder 中打开", systemImage: "folder")
                            }
                            .disabled(controller.isBusy)
                            Button("刷新") { controller.refreshSnapshots() }
                                .disabled(controller.isBusy)
                        }
                    }
                    Divider().padding(.vertical, 2)
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("保存后自动创建快照", isOn: $controller.autoBackupEnabled)
                            .disabled(controller.isValidation)
                        Toggle("每日自动创建一次本地快照", isOn: $controller.dailyAutoBackupEnabled)
                            .disabled(controller.isValidation)
                        Toggle("退出前自动备份本次改动", isOn: $controller.backupOnQuitEnabled)
                            .disabled(controller.isValidation)
                        Text("自动快照在保存静置 20 秒、距上次快照超过 24 小时或退出前存在新改动时静默执行，不阻塞写作。")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
            }

            statusSection

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("快照", systemImage: "clock.arrow.circlepath").font(.headline)
                        Spacer()
                        Text("保留最近 \(BackupService.defaultRetention) 个完整快照")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    if controller.snapshots.isEmpty {
                        Text("还没有可恢复的快照。").font(.system(size: 12))
                            .foregroundStyle(.secondary).padding(.vertical, 6)
                    } else {
                        ForEach(controller.snapshots) { snapshot in
                            snapshotRow(snapshot)
                            if snapshot.id != controller.snapshots.last?.id { Divider() }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
            }

            Text("本地目录备份默认将完整快照写入你授权的文件夹（含 Entries 与废纸篓，私密日记保持密文）；若选择 iCloud Drive 目录，云端上传由系统异步完成。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(width: 640)
        .disabled(controller.isBusy)
        .interactiveDismissDisabled(controller.isBusy)
        .task { await controller.load() }
        .confirmationDialog(
            "恢复快照？",
            isPresented: Binding(
                get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }
            ), presenting: pendingRestore
        ) { pending in
            Button("恢复到所选目录", role: .destructive) {
                controller.restore(snapshot: pending.snapshot, to: pending.target)
                pendingRestore = nil
            }
            Button("取消", role: .cancel) { pendingRestore = nil }
        } message: { pending in
            Text(
                "将把 \(pending.snapshot.manifest.activeCount) 篇日记和 \(pending.snapshot.manifest.trashedCount) 篇废纸篓日记恢复到：\n\(pending.target.path)\n目标目录已有日记文件或 Trash 非空时会拒绝写入。"
            )
        }
    }

    private var statusSection: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(
                systemName: controller.status.isFailure
                    ? "exclamationmark.triangle.fill"
                    : controller.status.isWorking ? "arrow.triangle.2.circlepath" : "checkmark.circle"
            )
            .foregroundStyle(
                controller.status.isFailure
                    ? .orange : controller.status.isWorking ? .secondary : DiaryStyle.accent
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(controller.status.label).font(.system(size: 12))
                if controller.hasDirectory {
                    Text("云端状态：\(controller.cloudState.label)")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if controller.isBusy { ProgressView().controlSize(.small) }
        }
    }

    private func snapshotRow(_ snapshot: BackupSnapshotSummary) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(
                    snapshot.manifest.createdAt.formatted(
                        date: .abbreviated, time: .standard)
                ).font(.system(size: 12, weight: .medium))
                Text(
                    "\(snapshot.manifest.activeCount) 篇日记 · 废纸篓 \(snapshot.manifest.trashedCount) 篇 · \(formattedBytes(snapshot.manifest.totalBytes))"
                ).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("验证并恢复…") { chooseRestoreTarget(for: snapshot) }
                .disabled(controller.isBusy)
        }
        .padding(.vertical, 4)
    }

    private func chooseBackupDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "选择备份目录"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        controller.grantDirectory(url)
    }

    private func chooseRestoreTarget(for snapshot: BackupSnapshotSummary) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "恢复到此目录"
        panel.message = "请选择一个空目录或新目录；目标已有日记文件或 Trash 非空时会拒绝写入。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        pendingRestore = PendingRestore(snapshot: snapshot, target: url)
    }

    private func formattedBytes(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }
}

struct PendingRestore: Identifiable {
    let snapshot: BackupSnapshotSummary
    let target: URL
    var id: UUID { snapshot.id }
}
