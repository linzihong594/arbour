import DiaryState
import SwiftUI

struct TrashDetailView: View {
    let workspace: DiaryWorkspace

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "trash").font(.system(size: 36, weight: .light))
                .foregroundStyle(DiaryStyle.accent)
            Text(workspace.selectedTrashEntry?.metadata.title ?? L10n.tr("废纸篓", "Trash"))
                .font(.system(size: 23, design: .serif))
                .multilineTextAlignment(.center).lineLimit(3)
            Text(
                L10n.tr(
                    "日记原文保留在这台 Mac 上。恢复后可以继续阅读和编辑。",
                    "The original entry is safely kept on this Mac. Restore it to continue reading and editing."
                )
            )
            .font(.system(size: 12)).foregroundStyle(.secondary)
            if workspace.selectedTrashEntry != nil {
                Button(L10n.tr("恢复这篇日记", "Restore Entry")) { Task { await workspace.restoreSelected() } }
                    .buttonStyle(.borderedProminent).disabled(workspace.isBusy)
            }
        }
        .padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
