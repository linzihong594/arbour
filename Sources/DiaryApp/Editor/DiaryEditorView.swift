import DiaryEditing
import DiaryState
import SwiftUI

struct DiaryEditorView: View {
    let workspace: DiaryWorkspace
    var openMapPicker: (() -> Void)? = nil
    @ViewState<Bool> private var showsSource = false

    var body: some View {
        let identity = workspace.editorIdentity
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Text(dateLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    if let location = workspace.location {
                        Label(location.displayText, systemImage: "location")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.quaternary.opacity(0.45), in: Capsule())
                            .help(location.source == .manual ? "地图选点" : "单次定位")
                    } else if let openMapPicker, !workspace.isLocked {
                        Button(action: openMapPicker) {
                            Label("记下地点", systemImage: "mappin")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help("在地图上选点")
                    }

                    if let weather = workspace.weather {
                        Label(weather.summaryText, systemImage: weather.symbolName)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.quaternary.opacity(0.45), in: Capsule())
                            .help(
                                "\(weather.source) · "
                                    + "\(weather.fetchedAt.formatted(date: .omitted, time: .shortened)) 请求"
                            )
                    }

                    if workspace.isWeatherLoading {
                        ProgressView().controlSize(.mini)
                    }

                    Spacer(minLength: 8)

                    Toggle("Markdown 原文", isOn: $showsSource)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .help("切换模式会重建编辑器，并清除本篇的撤销历史。")
                }

                TextField(
                    "给今天一个标题",
                    text: Binding(
                        get: {
                            workspace.editorIdentity == identity
                                ? workspace.selectedEntry?.metadata.title ?? "" : ""
                        },
                        set: { if let identity { workspace.setTitle($0, from: identity) } }
                    )
                )
                .textFieldStyle(.plain)
                .font(.system(size: 30, weight: .medium, design: .serif))
                .lineLimit(1)
                .accessibilityLabel("日记标题")

                Rectangle()
                    .fill(DiaryStyle.paperBorder)
                    .frame(height: 1)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 44)
            .padding(.top, 34)
            .padding(.bottom, 18)

            DiaryEditorSurface(
                text: Binding(
                    get: { workspace.editorIdentity == identity ? workspace.markdown : "" },
                    set: { if let identity { workspace.setMarkdown($0, from: identity) } }),
                documentID: workspace.selectedID?.uuidString ?? "empty",
                showsSource: showsSource,
                isEditable: !workspace.isBusy
            )
            .padding(.horizontal, 40)
            .accessibilityLabel("日记正文")

            HStack(spacing: 12) {
                Text("\(workspace.markdown.count) 字")
                if let status = workspace.weatherStatus {
                    Text(status).foregroundStyle(.orange).lineLimit(1)
                }
                Spacer()
                if workspace.session?.autosave.status == .saving {
                    ProgressView().controlSize(.mini)
                }
                Label(
                    workspace.session?.autosave.status.label ?? "",
                    systemImage: workspace.selectedEntry?.content.isEncrypted == true
                        ? "lock.shield" : "checkmark.circle"
                )
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 44)
            .padding(.vertical, 14)
        }
        .disabled(workspace.isBusy)
    }

    private var dateLabel: String {
        guard let metadata = workspace.selectedEntry?.metadata, let date = metadata.diaryDate else {
            return ""
        }
        var style = Date.FormatStyle.dateTime.year().month(.wide).day().weekday(.wide).locale(
            Locale(identifier: "zh_CN"))
        style.timeZone = TimeZone(identifier: metadata.timeZoneID) ?? .current
        return date.formatted(style)
    }
}
