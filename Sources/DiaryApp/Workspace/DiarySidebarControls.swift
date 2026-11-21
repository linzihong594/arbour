import DiaryState
import SwiftUI

struct DiarySidebarControls: View {
    let workspace: DiaryWorkspace
    @ViewState<Bool> private var showsDatePicker = false
    @ViewState<Date> private var date = .now

    var body: some View {
        VStack(spacing: 12) {
            Picker(
                L10n.tr("日记范围", "Scope"),
                selection: Binding(
                    get: { workspace.isShowingTrash },
                    set: { showing in Task { await workspace.showTrash(showing) } }
                )
            ) {
                Text(L10n.tr("日记", "Entries")).tag(false)
                Text(
                    L10n.tr(
                        "废纸篓 \(workspace.trashedEntries.count)", "Trash \(workspace.trashedEntries.count)")
                )
                .tag(true)
            }.pickerStyle(.segmented).labelsHidden()
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(
                    L10n.tr("搜索标题", "Search titles"),
                    text: Binding(
                        get: { workspace.filter.titleQuery }, set: { workspace.filter.titleQuery = $0 }
                    )
                )
                .textFieldStyle(.plain)
                .accessibilityLabel(L10n.tr("搜索日记标题", "Search diary titles"))
                if !workspace.filter.titleQuery.isEmpty {
                    Button {
                        workspace.filter.titleQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }.buttonStyle(.plain).help(L10n.tr("清除搜索", "Clear Search"))
                }
            }
            .padding(9)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Button {
                    showsDatePicker = true
                } label: {
                    Label(workspace.filter.day ?? L10n.tr("全部日期", "All Dates"), systemImage: "calendar")
                }
                .popover(isPresented: $showsDatePicker) {
                    VStack(spacing: 14) {
                        DatePicker(
                            L10n.tr("浏览日期", "Browse Date"), selection: $date, displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                        HStack {
                            Button(L10n.tr("全部日期", "All Dates")) {
                                workspace.filter.day = nil
                                showsDatePicker = false
                            }
                            Spacer()
                            Button(L10n.tr("按这一天筛选", "Filter by Day")) {
                                var calendar = Calendar(identifier: .gregorian)
                                calendar.timeZone = .current
                                let parts = calendar.dateComponents([.year, .month, .day], from: date)
                                workspace.filter.day = String(
                                    format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
                                showsDatePicker = false
                            }.buttonStyle(.borderedProminent)
                        }
                    }.padding(18).frame(width: 300)
                }
                if workspace.filter.day != nil {
                    Button {
                        workspace.filter.day = nil
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .help(L10n.tr("显示全部日期", "Show All Dates"))
                }
                Spacer()
                Text(
                    L10n.tr(
                        "\(workspace.visibleEntries.count) 篇",
                        "\(workspace.visibleEntries.count)"
                    )
                ).foregroundStyle(.tertiary)
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
    }
}
