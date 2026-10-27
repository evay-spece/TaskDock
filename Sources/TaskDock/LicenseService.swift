import AppKit
import Foundation
import Security
import SwiftUI

struct LicenseActivationResult {
    let isSuccess: Bool
    let message: String
    var title: String { isSuccess ? "激活成功" : "激活失败" }
}

private struct BetaTrialState: Codable {
    var expiry: Double = 0
    var redeemed: [String] = []
}

@MainActor
final class LicenseService: ObservableObject {
    @Published private(set) var isUnlocked = false
    @Published private(set) var remainingDays = 0
    @Published private(set) var message = ""
    @Published private(set) var paymentQRCode: NSImage?
    @Published private(set) var paymentQRCodeURL: URL?
    @Published private(set) var activatedLicenseCode = ""
    @Published private(set) var hasPermanentTrial = false
    @Published private(set) var pendingBuyerEmail = ""

    private let keychain: TaskDockKeychain
    private let defaults: UserDefaults
    private let clock: () -> Date
    private let testingPublicKeyPEM: String?
    private let openURL: (URL) -> Bool
    private var trialTimer: Timer?
    private let trialLength: TimeInterval = 7 * 24 * 60 * 60
    private var cachedDeviceID: String?
    private var selectedProvider = ""

    init(
        keychainService: String = "com.taskdock.license",
        defaults: UserDefaults = .standard,
        clock: @escaping () -> Date = Date.init,
        testingPublicKeyPEM: String? = nil,
        openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }
    ) {
        keychain = TaskDockKeychain(service: keychainService)
        self.defaults = defaults
        self.clock = clock
        self.testingPublicKeyPEM = testingPublicKeyPEM
        self.openURL = openURL
    }

    var deviceID: String {
        cachedDeviceID ?? keychain.readString("device-id") ?? ""
    }

    private var settings: [String: String] {
        guard let url = TaskDockLicenseResources.url(name: "Billing", ext: "plist"),
              let values = NSDictionary(contentsOf: url) as? [String: String] else { return [:] }
        return values
    }

    var supportEmail: String { settings["SupportEmail"] ?? "" }

    func start(scheduleTimer: Bool = true) {
        do {
            try ensureDeviceID()
        } catch {
            message = "无法将本机申请码保存到钥匙串，请检查钥匙串权限后重试。"
            return
        }
        if let saved = keychain.readString("license-token"), verify(token: saved) {
            activatedLicenseCode = saved
        }
        pendingBuyerEmail = keychain.readString("purchase-email") ?? ""
        evaluateLicenseAndTrial()
        if scheduleTimer && trialTimer == nil {
            trialTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.evaluateLicenseAndTrial() }
            }
        }
    }

    private func evaluateLicenseAndTrial() {
        hasPermanentTrial = keychain.readString("permanent-trial") == "enabled"
        if hasPermanentTrial {
            isUnlocked = true
            remainingDays = 0
            message = "永久试用已开启"
            return
        }
        // Paid licenses do not depend on the clock or any online service.
        if let token = keychain.readString("license-token"), verify(token: token) {
            isUnlocked = true
            remainingDays = 0
            return
        }
        let now = clock().timeIntervalSince1970
        let legacyLastSeen = (defaults.object(forKey: "taskdock.trial.latestSeen.v1") as? Date)?.timeIntervalSince1970 ?? 0
        let lastSeen = max(keychain.readString("last-seen").flatMap(Double.init) ?? 0, legacyLastSeen)
        if now < lastSeen - 300 {
            remainingDays = 0
            isUnlocked = false
            message = "检测到系统时间回拨，请校准日期后重试。"
            return
        }
        do { try keychain.writeString(String(max(now, lastSeen)), account: "last-seen") }
        catch { isUnlocked = false; message = "无法保存试用状态到钥匙串。"; return }
        let firstLaunch: Double
        if let saved = keychain.readString("trial-start").flatMap(Double.init) {
            firstLaunch = saved
        } else {
            let legacy = (defaults.object(forKey: "taskdock.trial.firstUse.v1") as? Date)?.timeIntervalSince1970
            firstLaunch = min(now, legacy ?? now)
            do { try keychain.writeString(String(firstLaunch), account: "trial-start") }
            catch { isUnlocked = false; message = "无法保存试用状态到钥匙串。"; return }
        }
        let extendedExpiry: Double
        if let saved = keychain.readString("trial-expiry").flatMap(Double.init) {
            extendedExpiry = saved
        } else {
            extendedExpiry = (defaults.object(forKey: "taskdock.trial.extensionExpiry.v1") as? Date)?.timeIntervalSince1970 ?? 0
            do { try keychain.writeString(String(extendedExpiry), account: "trial-expiry") }
            catch { isUnlocked = false; message = "无法保存试用状态到钥匙串。"; return }
        }
        let betaExpiry: Double
        do { betaExpiry = try loadBetaTrialState().expiry }
        catch { isUnlocked = false; message = "无法读取内测试用状态，请联系客服。"; return }
        let remaining = max(0, max(firstLaunch + trialLength, max(extendedExpiry, betaExpiry)) - max(now, lastSeen))
        remainingDays = Int(ceil(remaining / (24 * 60 * 60)))
        isUnlocked = remaining > 0
        if isUnlocked { message = "" }
    }

    func refreshStatus() {
        evaluateLicenseAndTrial()
    }

    func clearPaymentSelection() {
        selectedProvider = ""
        paymentQRCode = nil
        paymentQRCodeURL = nil
        message = ""
    }

    private func ensureDeviceID() throws {
        if let existing = keychain.readString("device-id"), UUID(uuidString: existing) != nil {
            cachedDeviceID = existing
            return
        }
        let value = UUID().uuidString.lowercased()
        try keychain.writeString(value, account: "device-id")
        cachedDeviceID = value
    }

    func beginPurchase(provider: String, email: String) {
        clearPaymentSelection()
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard email.range(of: "^[^\\s@,;<>]+@[^\\s@,;<>]+\\.[^\\s@,;<>]+$", options: .regularExpression) != nil,
              ["alipay", "wechat"].contains(provider) else { message = "请填写有效的接收邮箱。"; return }
        let qrURL = ["jpg", "png", "jpeg"].compactMap { ext in
            TaskDockLicenseResources.url(name: "payment-\(provider)", ext: ext)
        }.first
        guard let qrURL,
              let image = NSImage(contentsOf: qrURL), !supportEmail.isEmpty else {
            message = "收款码或客服邮箱尚未配置，请联系软件提供方。"
            paymentQRCode = nil
            paymentQRCodeURL = nil
            return
        }
        do {
            try ensureDeviceID()
            try keychain.writeString(email, account: "purchase-email")
            pendingBuyerEmail = email
            selectedProvider = provider
            paymentQRCode = image
            paymentQRCodeURL = qrURL
            message = "请扫码支付 ¥59。付款后打开申请邮件并主动发送，或复制申请信息后通过网页邮箱发送至客服。核款后由客服人工回信发码。"
        } catch {
            message = "无法保存申请信息，请检查钥匙串权限后重试。"
        }
    }

    func openPaymentQRCode() {
        guard let url = paymentQRCodeURL else { return }
        if !openURL(url) {
            message = "无法打开收款码原图，请使用当前窗口中的二维码。"
        }
    }

    var purchaseRequest: String {
        """
        TaskDock 授权申请
        收件邮箱：\(pendingBuyerEmail)
        本机申请码：\(deviceID)
        支付方式：\(selectedProvider == "wechat" ? "微信" : "支付宝")
        金额：¥59
        付款时间：请填写
        付款流水号：请填写
        """
    }

    var canPreparePurchaseRequest: Bool {
        !supportEmail.isEmpty && !pendingBuyerEmail.isEmpty && !deviceID.isEmpty &&
            ["alipay", "wechat"].contains(selectedProvider) && paymentQRCodeURL != nil
    }

    var purchaseRequestMailURL: URL? {
        guard canPreparePurchaseRequest else { return nil }
        var mail = URLComponents()
        mail.scheme = "mailto"
        mail.path = supportEmail
        mail.queryItems = [URLQueryItem(name: "subject", value: "TaskDock 付款与激活申请"),
                           URLQueryItem(name: "body", value: purchaseRequest)]
        return mail.url
    }

    func openPurchaseRequestDraft() {
        guard let url = purchaseRequestMailURL else {
            message = "请先确认邮箱并选择收款方式。"
            return
        }
        guard openURL(url) else {
            message = "未能打开邮件客户端，请复制申请信息并手动发送至 \(supportEmail)。"
            return
        }
        message = "已请求打开邮件草稿，这不代表已发送。请补充付款时间和流水号，再在邮箱中点击发送。未配置邮件客户端时，请复制申请信息并通过网页邮箱发送。"
    }

    @discardableResult
    func activate(code: String) -> LicenseActivationResult {
        do { try ensureDeviceID() }
        catch { return activationResult(false, "无法保存本机申请码到钥匙串，请检查权限后重试。") }
        let token = code.components(separatedBy: .whitespacesAndNewlines).joined()
        if token.lowercased() == "whosyourdaddy" {
            do {
                try keychain.writeString("enabled", account: "permanent-trial")
                evaluateLicenseAndTrial()
                return activationResult(true, "永久试用已开启，可离线使用。")
            } catch { return activationResult(false, "无法保存永久试用状态，请检查钥匙串权限。") }
        }
        if !token.contains(".") || token.hasPrefix("TD7.") {
            return redeemBetaCode(code)
        }
        guard verify(token: token) else {
            return activationResult(false, "购买授权激活码无效或不属于本机。请完整复制邮件中的长激活码；换机需重新申请。")
        }
        do {
            try keychain.writeString(token, account: "license-token")
            activatedLicenseCode = token
            paymentQRCode = nil
            paymentQRCodeURL = nil
            evaluateLicenseAndTrial()
            return activationResult(true, "TaskDock 已激活，可离线使用。")
        } catch {
            return activationResult(false, "激活码验证通过，但无法保存到钥匙串。请检查权限后重试。")
        }
    }

    private func activationResult(_ success: Bool, _ text: String) -> LicenseActivationResult {
        message = text
        return LicenseActivationResult(isSuccess: success, message: text)
    }

    private func loadBetaTrialState() throws -> BetaTrialState {
        guard let value = keychain.readString("beta-trial-state") else { return BetaTrialState() }
        return try JSONDecoder().decode(BetaTrialState.self, from: Data(value.utf8))
    }

    private func redeemBetaCode(_ code: String) -> LicenseActivationResult {
        guard activatedLicenseCode.isEmpty else {
            return activationResult(false, "本机已购买授权，无需兑换增加试用天数的内测码。")
        }
        do {
            guard let pemURL = TaskDockLicenseResources.url(name: BetaCode.publicKeyResource, ext: "pem"),
                  let hashesURL = TaskDockLicenseResources.url(name: BetaCode.shortCodeHashesResource, ext: "txt") else {
                throw BetaCodeError.unavailable
            }
            let identifier = try BetaCode.identifier(in: code,
                publicKeyPEM: String(contentsOf: pemURL, encoding: .utf8),
                shortCodeHashes: BetaCode.shortCodeHashes(from: String(contentsOf: hashesURL, encoding: .utf8)))
            var state = try loadBetaTrialState()
            let legacyRedeemed = defaults.stringArray(forKey: "taskdock.trial.redeemedCodeIDs.v1") ?? []
            guard !state.redeemed.contains(identifier), !legacyRedeemed.contains(identifier) else {
                throw BetaCodeError.alreadyUsed
            }
            let now = clock().timeIntervalSince1970
            let lastSeen = max(keychain.readString("last-seen").flatMap(Double.init) ?? 0,
                (defaults.object(forKey: "taskdock.trial.latestSeen.v1") as? Date)?.timeIntervalSince1970 ?? 0)
            guard now >= lastSeen - 300 else {
                return activationResult(false, "检测到系统时间回拨，请校准日期后重试。")
            }
            let first = keychain.readString("trial-start").flatMap(Double.init) ?? now
            let priorExpiry = max(keychain.readString("trial-expiry").flatMap(Double.init) ?? 0,
                (defaults.object(forKey: "taskdock.trial.extensionExpiry.v1") as? Date)?.timeIntervalSince1970 ?? 0)
            state.expiry = max(max(now, lastSeen), max(first + trialLength, max(priorExpiry, state.expiry))) + trialLength
            state.redeemed = Array(Set(state.redeemed + legacyRedeemed + [identifier])).sorted()
            let encoded = try JSONEncoder().encode(state)
            try keychain.writeString(String(decoding: encoded, as: UTF8.self), account: "beta-trial-state")
            evaluateLicenseAndTrial()
            let until = DateFormatter.localizedString(from: Date(timeIntervalSince1970: state.expiry),
                dateStyle: .long, timeStyle: .short)
            return activationResult(true, "内测码兑换成功，已增加 7 天试用，可使用至 \(until)。此码为内测试用码。")
        } catch let error as BetaCodeError {
            return activationResult(false, error.localizedDescription)
        } catch {
            return activationResult(false, "无法读取或保存内测试用状态，请检查钥匙串权限后重试。")
        }
    }

    private func verify(token: String) -> Bool {
        guard !deviceID.isEmpty else { return false }
        let pem: String
        if let testingPublicKeyPEM {
            pem = testingPublicKeyPEM
        } else {
            guard let url = TaskDockLicenseResources.url(name: "license-public-key", ext: "pem"),
                  let loaded = try? String(contentsOf: url, encoding: .utf8) else { return false }
            pem = loaded
        }
        return OfflineLicenseVerifier.verify(token: token, deviceID: deviceID, pem: pem)
    }
}

private struct TaskDockKeychain {
    let service: String

    func readString(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func writeString(_ value: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let data = Data(value.utf8)
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(updateStatus))
        }
        var item = query
        item[kSecValueData as String] = data
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }

    func delete(_ account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}
