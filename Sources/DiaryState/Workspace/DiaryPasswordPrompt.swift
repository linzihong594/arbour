import Foundation
import Observation

/// A password request belongs to one session and one operation, even if the window changes behind it.
@MainActor @Observable
public final class DiaryPasswordPrompt {
    public var password = ""
    public var confirmation = ""
    public private(set) var errorMessage: String?
    public private(set) var isWorking = false
    public let isUnlocking: Bool
    private weak var workspace: DiaryWorkspace?
    private weak var target: DiarySession?
    private var cancelled = false

    public init(workspace: DiaryWorkspace) {
        self.workspace = workspace
        target = workspace.session
        isUnlocking = workspace.isLocked
    }

    public func submit() async -> Bool {
        guard !cancelled, !isWorking else { return false }
        guard let workspace, let target, workspace.session === target, !workspace.isBusy,
            target.isLocked == isUnlocking, target.document.content.isEncrypted == isUnlocking
        else {
            clearInputs()
            errorMessage = "日记状态已改变，请重新打开密码面板。"
            return false
        }
        let provided = password
        let repeated = confirmation
        clearInputs()
        errorMessage = nil
        guard !provided.isEmpty else {
            errorMessage = "请输入密码。"
            return false
        }
        if !isUnlocking {
            guard provided.count >= 8 else {
                errorMessage = "密码至少需要 8 个字符。"
                return false
            }
            guard provided == repeated else {
                errorMessage = "两次输入的密码不一致。"
                return false
            }
        }
        isWorking = true
        defer { isWorking = false }
        let success =
            isUnlocking
            ? await workspace.unlock(password: provided)
            : await workspace.encrypt(password: provided)
        guard !cancelled else { return false }
        if !success {
            errorMessage = workspace.errorMessage ?? target.errorMessage ?? "操作已取消，请重试。"
            workspace.errorMessage = nil
            target.errorMessage = nil
        }
        return success
    }

    public func cancel() {
        cancelled = true
        clearInputs()
        errorMessage = nil
        if isWorking && isUnlocking { target?.lock() }
    }

    private func clearInputs() {
        password = ""
        confirmation = ""
    }
}
