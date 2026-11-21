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
                Text(L10n.tr("有些心事，只留给自己", "Some thoughts are meant for you alone"))
                    .font(.system(size: 19, weight: .medium, design: .serif))
                Text(
                    touchID == nil
                        ? L10n.tr("输入密码，打开这篇日记。", "Enter your password to unlock this entry.")
                        : L10n.tr("使用 Touch ID 或日记密码打开。", "Unlock with Touch ID or your password.")
                )
                .font(.system(size: 12)).foregroundStyle(.secondary)
                if let touchID {
                    Button(action: touchID) {
                        Label(L10n.tr("使用 Touch ID", "Unlock with Touch ID"), systemImage: "touchid")
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                }
                Button(
                    touchID == nil
                        ? L10n.tr("解锁日记", "Unlock Entry")
                        : L10n.tr("使用日记密码", "Use Password"),
                    action: unlock
                )
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 4)
                if isBusy { ProgressView(L10n.tr("正在验证…", "Verifying…")).controlSize(.small) }
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
