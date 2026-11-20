import AppKit
import CryptoKit
import DiaryPlatform
import SwiftUI

struct CapabilityView: View {
    @Environment(\.dismiss) private var dismiss
    @ViewState<Bool> private var isBusy = false
    @ViewState<String?> private var biometricResult = nil
    private let keyStore = BiometricKeyStore()
    private let signing = BiometricSigningStatus.current()

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("系统能力验证").font(.system(size: 22, weight: .medium, design: .serif))
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("这里使用合成密钥和临时测试文件，不读取你的日记。")
                .font(.system(size: 12)).foregroundStyle(.secondary)

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Touch ID", systemImage: "touchid").font(.headline)
                    Text(keyStore.availability().description).font(.system(size: 12))
                    Text(
                        signing.isConfigured
                            ? "当前构建已配置签名标识与描述文件，仍需实际认证验证。"
                            : "当前构建未配置 Touch ID 签名授权，日记密码仍可使用。"
                    )
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    Text("点击后由系统请求指纹，以验证 Keychain 是否真的在认证后释放测试密钥。测试结束即删除该密钥。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Button("验证 Touch ID") { verifyBiometrics() }
                        .disabled(!signing.isConfigured || !keyStore.availability().isAvailable)
                    if let biometricResult { Text(biometricResult).font(.system(size: 12)) }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(10)
            }
            if isBusy { ProgressView().controlSize(.small) }
        }
        .padding(30)
        .frame(width: 560)
        .disabled(isBusy)
        .interactiveDismissDisabled(isBusy)
    }

    private func verifyBiometrics() {
        isBusy = true
        biometricResult = nil
        Task {
            do {
                try await Task.detached {
                    let store = BiometricKeyStore()
                    let id = UUID()
                    let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
                    try store.save(key, id: id)
                    do {
                        let retrieved = try store.read(id: id, reason: "验证日记应用的测试解密密钥")
                        guard retrieved == key else {
                            throw PlatformError.message("返回的测试密钥不一致。")
                        }
                        try store.remove(id: id)
                    } catch {
                        try? store.remove(id: id)
                        throw error
                    }
                }.value
                biometricResult = "验证通过：系统认证后已取回测试密钥，并完成删除。"
            } catch {
                biometricResult = error.localizedDescription
            }
            isBusy = false
        }
    }
}
