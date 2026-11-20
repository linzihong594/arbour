import DiaryState
import SwiftUI

struct DiarySidebarControls: View {
    let workspace: DiaryWorkspace
    @ViewState<Bool> private var showsDatePicker = false
    @ViewState<Date> private var date = .now

    var body: some View {
        VStack(spacing: 12) {
            Picker(
                "日记范围",
                selection: Binding(
                    get: { workspace.isShowingTrash },
                    set: { showing in Task { await workspace.showTrash(showing) } }
                )
            ) {
                Text("日记").tag(false)
                Text("废纸篓 \(workspace.trashedEntries.count)").tag(true)
            }.pickerStyle(.segmented).labelsHidden()
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(
                    "搜索标题",
                    text: Binding(
                        get: { workspace.filter.titleQuery }, set: { workspace.filter.titleQuery = $0 }
                    )
                )
                .textFieldStyle(.plain)
                .accessibilityLabel("搜索日记标题")
                if !workspace.filter.titleQuery.isEmpty {
                    Button {
                        workspace.filter.titleQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }.buttonStyle(.plain).help("清除搜索")
                }
            }
            .padding(9)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Button {
                    showsDatePicker = true
                } label: {
                    Label(workspace.filter.day ?? "全部日期", systemImage: "calendar")
                }
                .popover(isPresented: $showsDatePicker) {
                    VStack(spacing: 14) {
                        DatePicker("浏览日期", selection: $date, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                        HStack {
                            Button("全部日期") {
                                workspace.filter.day = nil
                                showsDatePicker = false
                            }
                            Spacer()
                            Button("按这一天筛选") {
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
                    .help("显示全部日期")
                }
                Spacer()
                Text("\(workspace.visibleEntries.count) 篇").foregroundStyle(.tertiary)
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
    }
}
