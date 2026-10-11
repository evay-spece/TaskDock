import AppKit

@MainActor
enum BetaActivationUI {
    @discardableResult
    static func prompt(trial: TrialManager) -> Bool {
        let alert = NSAlert()
        alert.messageText = trial.isExpired() ? "TaskDock 内测试用已结束" : "输入 TaskDock 内测激活码"
        alert.informativeText = "每个激活码增加 7 天试用，同一个码在此安装中只能使用一次。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "激活")
        alert.addButton(withTitle: "取消")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 28))
        field.placeholderString = "粘贴内测激活码"
        alert.accessoryView = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        do {
            guard let path = Bundle.main.path(forResource: BetaCode.publicKeyResource, ofType: "pem"),
                  let pem = try? String(contentsOfFile: path, encoding: .utf8),
                  let hashesPath = Bundle.main.path(
                    forResource: BetaCode.shortCodeHashesResource, ofType: "txt"
                  ),
                  let hashesText = try? String(contentsOfFile: hashesPath, encoding: .utf8) else {
                throw BetaCodeError.unavailable
            }
            let expiry = try trial.redeem(
                field.stringValue,
                publicKeyPEM: pem,
                shortCodeHashes: BetaCode.shortCodeHashes(from: hashesText)
            )
            let confirmation = NSAlert()
            confirmation.messageText = "已增加 7 天试用"
            confirmation.informativeText = "可使用至 \(DateFormatter.localizedString(from: expiry, dateStyle: .long, timeStyle: .short))。"
            confirmation.addButton(withTitle: "好")
            confirmation.runModal()
            return true
        } catch {
            let failure = NSAlert(error: error)
            failure.runModal()
            return false
        }
    }
}
