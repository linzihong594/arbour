import SwiftUI

struct LockedDiaryView: View {
    let unlock: () -> Void
    var touchID: (() -> Void)? = nil
    var isBusy = false
    var unavailableReason: String? = nil

    var body: some View {
        ZStack {
            // Decorative placeholders never contain the decrypted diary.
            VStack(alignment: .leading, spacing: 19) {
                ForEach(0..<9) { index in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.secondary.opacity(0.18))
                        .frame(width: index.isMultiple(of: 3) ? 260 : 390, height: 10)
                }
            }
            .blur(radius: 7)
            .accessibilityHidden(true)

            VStack(spacing: 16) {
                Image(systemName: "lock")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(DiaryStyle.accent)
                Text("有些心事，只留给自己")
                    .font(.system(size: 19, weight: .medium, design: .serif))
                Text(touchID == nil ? "输入密码，打开这篇日记。" : "使用 Touch ID 或日记密码打开。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                if let touchID {
                    Button(action: touchID) { Label("使用 Touch ID", systemImage: "touchid") }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                }
                Button(touchID == nil ? "解锁日记" : "使用日记密码", action: unlock)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 4)
                if isBusy { ProgressView("正在验证…").controlSize(.small) }
                if let unavailableReason {
                    Text(unavailableReason).font(.system(size: 11)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).frame(maxWidth: 300)
                }
            }
            .padding(34)
            .background(DiaryStyle.page.opacity(0.96), in: RoundedRectangle(cornerRadius: 20))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .disabled(isBusy)
    }
}
