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
                    Text("栖木").font(.system(size: 22, weight: .semibold, design: .serif))
                    Text("把一天，轻轻收好")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await workspace.addEntry() }
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .buttonStyle(.borderless)
                .help("新建日记")
            }
            .padding(.horizontal, 22)
            .padding(.top, 48)
            .padding(.bottom, 20)

            DiarySidebarControls(workspace: workspace)

            DiaryEntryList(workspace: workspace)

            VStack(alignment: .leading, spacing: 6) {
                Label(isDemo ? "独立示例库" : "本地日记", systemImage: isDemo ? "circle.dotted" : "internaldrive")
                    .font(.system(size: 11, weight: .medium))
                Text(isDemo ? "合成示例独立保存，不混入本地日记。" : "自动保存在这台 Mac 上。")
                    .font(.system(size: 10))
            }
            .foregroundStyle(.secondary)
            .padding(22)
        }
        .background(DiaryStyle.sidebar)
        .disabled(workspace.isBusy)
    }

}
