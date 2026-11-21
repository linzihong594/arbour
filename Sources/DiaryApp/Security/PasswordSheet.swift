import DiaryState
import SwiftUI

struct PasswordSheet: View {
    let workspace: DiaryWorkspace
    @Environment(\.dismiss) private var dismiss
    @ViewState<DiaryPasswordPrompt> private var prompt: DiaryPasswordPrompt
    @FocusState private var passwordFocused: Bool

    private var isUnlocking: Bool { prompt.isUnlocking }

    init(workspace: DiaryWorkspace) {
        self.workspace = workspace
        _prompt = ViewState(wrappedValue: DiaryPasswordPrompt(workspace: workspace))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label(
                isUnlocking
                    ? L10n.tr("打开私密日记", "Unlock Private Entry")
                    : L10n.tr("为这篇日记设置密码", "Encrypt This Entry"),
                systemImage: "lock.shield"
            )
            .font(.system(size: 20, weight: .medium, design: .serif))
            Text(
                isUnlocking
                    ? L10n.tr("密码只用于本机解密。", "Your password is used strictly for local decryption.")
                    : L10n.tr(
                        "正文将被加密，标题继续可见。请记住密码，当前没有密码找回功能。",
                        "The body will be encrypted while the title stays visible. Remember your password — there is no password recovery."
                    )
            )
            .font(.system(size: 12)).foregroundStyle(.secondary)

            SecureField(
                isUnlocking
                    ? L10n.tr("输入密码", "Enter password")
                    : L10n.tr("至少 8 个字符", "At least 8 characters"),
                text: $prompt.password
            )
            .focused($passwordFocused)
            .onSubmit { submit() }
            if !isUnlocking {
                SecureField(L10n.tr("再次输入密码", "Confirm password"), text: $prompt.confirmation)
                    .onSubmit { submit() }
            }
            if let error = prompt.errorMessage {
                Text(error).font(.system(size: 12)).foregroundStyle(.red)
            }
            HStack {
                if prompt.isWorking { ProgressView().controlSize(.small) }
                Spacer()
                Button(L10n.tr("取消", "Cancel"), role: .cancel) {
                    prompt.cancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(
                    isUnlocking
                        ? L10n.tr("解锁", "Unlock")
                        : L10n.tr("加密并锁定", "Encrypt & Lock")
                ) { submit() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(prompt.password.isEmpty)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(30)
        .frame(width: 420)
        .disabled(prompt.isWorking || workspace.isBusy)
        .interactiveDismissDisabled(prompt.isWorking)
        .onAppear { passwordFocused = true }
        .onDisappear { prompt.cancel() }
    }

    private func submit() {
        Task {
            if await prompt.submit() {
                dismiss()
            } else {
                passwordFocused = true
            }
        }
    }
}
