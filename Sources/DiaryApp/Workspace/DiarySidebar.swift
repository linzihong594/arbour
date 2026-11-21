import DiaryState
import SwiftUI

struct DiarySidebar: View {
    let workspace: DiaryWorkspace
    var isDemo: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "book.closed")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(DiaryStyle.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.tr("栖木", "Arbour")).font(.system(size: 22, weight: .semibold, design: .serif))
                    Text(L10n.tr("把一天，轻轻收好", "Keep your days gently"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await workspace.addEntry() }
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .buttonStyle(.borderless)
                .help(L10n.tr("新建日记", "New Entry"))
            }
            .padding(.horizontal, 22)
            .padding(.top, 48)
            .padding(.bottom, 20)

            DiarySidebarControls(workspace: workspace)

            DiaryEntryList(workspace: workspace)

            VStack(alignment: .leading, spacing: 6) {
                Label(
                    isDemo
                        ? L10n.tr("独立示例库", "Isolated Demo Library")
                        : L10n.tr("本地日记", "Local Diary"),
                    systemImage: isDemo ? "circle.dotted" : "internaldrive"
                )
                .font(.system(size: 11, weight: .medium))
                Text(
                    isDemo
                        ? L10n.tr("合成示例独立保存，不混入本地日记。", "Demo entries stay isolated from your real library.")
                        : L10n.tr("自动保存在这台 Mac 上。", "Saved automatically on this Mac.")
                )
                .font(.system(size: 10))
            }
            .foregroundStyle(.secondary)
            .padding(22)
        }
        .background(DiaryStyle.sidebar)
        .disabled(workspace.isBusy)
    }

}
