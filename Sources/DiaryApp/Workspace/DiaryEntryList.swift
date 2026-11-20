import DiaryCore
import DiaryState
import SwiftUI

/// Lazy native controls avoid OutlineList's recursive row-height updates on large libraries.
struct DiaryEntryList: View {
    let workspace: DiaryWorkspace
    @FocusState private var focusedID: UUID?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(groups, id: \.key) { group in
                        Text(group.key)
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                            .padding(.horizontal, 12).padding(.top, 12)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(group.value) { entry in
                            row(entry).id(entry.id)
                                .focused($focusedID, equals: entry.id)
                        }
                    }
                }.padding(.horizontal, 10).padding(.bottom, 12)
            }
            .onChange(of: workspace.selectedID) { _, id in
                if let id { proxy.scrollTo(id) }
            }
            .overlay {
                if workspace.visibleEntries.isEmpty {
                    Text(
                        workspace.isShowingTrash && workspace.trashedEntries.isEmpty
                            ? "废纸篓是空的" : "没有符合条件的日记"
                    )
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func row(_ entry: DiarySummary) -> some View {
        let selected = entry.id == workspace.selectedID
        return Button {
            focusedID = entry.id
            Task { await workspace.select(entry.id) }
        } label: {
            HStack(spacing: 8) {
                Text(entry.metadata.title.isEmpty ? "无标题日记" : entry.metadata.title)
                    .font(.system(size: 14, weight: .medium)).lineLimit(1)
                Spacer(minLength: 0)
                if entry.isEncrypted { Image(systemName: "lock.fill").font(.system(size: 10)) }
            }
            .padding(.horizontal, 12).frame(height: 44)
            .contentShape(Rectangle())
            .background(
                selected ? DiaryStyle.accent.opacity(0.16) : .clear,
                in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .focusable()
        .onKeyPress(.upArrow) {
            moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveSelection(by: 1)
            return .handled
        }
        .accessibilityValue(entry.isEncrypted ? "私密日记" : "日记")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func moveSelection(by step: Int) {
        let entries = workspace.visibleEntries
        guard !workspace.isBusy, !entries.isEmpty else { return }
        let index = entries.firstIndex { $0.id == workspace.selectedID }
        let next = index.map { max(0, min(entries.count - 1, $0 + step)) } ?? 0
        Task {
            await workspace.select(entries[next].id)
            focusedID = workspace.selectedID
        }
    }

    private var groups: [(key: String, value: [DiarySummary])] {
        Dictionary(grouping: workspace.visibleEntries, by: \.metadata.day).sorted { $0.key > $1.key }
    }
}
