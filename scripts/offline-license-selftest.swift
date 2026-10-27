import AppKit
import Combine
import Foundation
import Security

@main
@MainActor
struct OfflineLicenseSelfTest {
    static func main() throws {
        let privateKey = try makeKey()
        let publicKey = SecKeyCopyPublicKey(privateKey)!
        let publicData = SecKeyCopyExternalRepresentation(publicKey, nil)! as Data
        let pem = "-----BEGIN RSA PUBLIC KEY-----\n\(publicData.base64EncodedString())\n-----END RSA PUBLIC KEY-----"
        let identifier = UUID().uuidString
        let service = "com.taskdock.sale-selftest.\(identifier)"
        let suite = "com.taskdock.sale-selftest.defaults.\(identifier)"
        let dockSuite = "com.taskdock.sale-selftest.dock.\(identifier)"
        let defaults = UserDefaults(suiteName: suite)!
        let dockDefaults = UserDefaults(suiteName: dockSuite)!
        defer {
            SecItemDelete([
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service
            ] as CFDictionary)
            defaults.removePersistentDomain(forName: suite)
            dockDefaults.removePersistentDomain(forName: dockSuite)
        }
        var now = Date(timeIntervalSince1970: 1_790_000_000)
        let beginning = now
        var openedURLs: [URL] = []
        let license = LicenseService(
            keychainService: service, defaults: defaults, clock: { now },
            testingPublicKeyPEM: pem, openURL: { openedURLs.append($0); return true })
        license.start(scheduleTimer: false)
        let device = license.deviceID
        precondition(UUID(uuidString: device) != nil)
        precondition(license.isUnlocked && license.remainingDays == 7)

        dockDefaults.set(true, forKey: "autohide")
        dockDefaults.set(0.4, forKey: "autohide-delay")
        let dock = SystemDockVisibilityController(
            domain: dockSuite, dockDefaults: dockDefaults, snapshotDefaults: defaults,
            restartDock: {})
        let observation = license.$isUnlocked.removeDuplicates().sink { unlocked in
            dock.synchronize(hidden: true, accessAllowed: unlocked)
        }
        defer { observation.cancel(); dock.restore() }
        precondition(dockDefaults.double(forKey: "autohide-delay") == 1000)
        now = beginning.addingTimeInterval(7 * 24 * 3600 - 1)
        license.refreshStatus()
        precondition(license.isUnlocked && license.remainingDays == 1)
        now = beginning.addingTimeInterval(7 * 24 * 3600)
        license.refreshStatus()
        precondition(!license.isUnlocked && license.remainingDays == 0)
        precondition(dockDefaults.double(forKey: "autohide-delay") == 0.4,
                     "Expiry must restore the user's exact Dock preferences")
        now = beginning
        license.refreshStatus()
        precondition(!license.isUnlocked, "Clock rollback must not restart a trial")

        precondition(license.purchaseRequestMailURL == nil)
        license.openPurchaseRequestDraft()
        precondition(openedURLs.isEmpty)
        let email = "buyer+taskdock@example.com"
        for provider in ["alipay", "wechat"] {
            license.beginPurchase(provider: provider, email: email)
            precondition(license.paymentQRCode != nil && license.canPreparePurchaseRequest)
            let mail = URLComponents(url: license.purchaseRequestMailURL!, resolvingAgainstBaseURL: false)!
            precondition(mail.scheme == "mailto" && mail.path == "53803736@qq.com")
            let subject = mail.queryItems?.first { $0.name == "subject" }?.value ?? ""
            let body = mail.queryItems?.first { $0.name == "body" }?.value ?? ""
            precondition(subject == "TaskDock 付款与激活申请")
            for value in [email, device, "¥59", "付款时间：请填写", "付款流水号：请填写",
                          provider == "wechat" ? "微信" : "支付宝"] {
                precondition(body.contains(value))
            }
            license.openPurchaseRequestDraft()
            precondition(license.message.contains("不代表已发送"))
        }
        precondition(openedURLs.count == 2)
        license.clearPaymentSelection()
        precondition(!license.canPreparePurchaseRequest && license.purchaseRequestMailURL == nil)
        precondition(license.paymentQRCodeURL == nil)
        license.beginPurchase(provider: "wechat", email: email)
        license.beginPurchase(provider: "invalid", email: email)
        precondition(!license.canPreparePurchaseRequest, "Invalid selections must discard old payment data")
        let failedOpener = LicenseService(
            keychainService: service, defaults: defaults, clock: { now },
            testingPublicKeyPEM: pem, openURL: { _ in false })
        failedOpener.start(scheduleTimer: false)
        failedOpener.beginPurchase(provider: "alipay", email: email)
        failedOpener.openPurchaseRequestDraft()
        precondition(failedOpener.message.contains("未能打开邮件客户端"))

        let token = try makeToken(privateKey, device: device, email: email)
        let parts = token.split(separator: ".").map(String.init)
        var changedPayload = Data(base64Encoded: normalizedBase64(parts[1]))!
        changedPayload[0] ^= 1
        let tampered = "\(parts[0]).\(base64URL(changedPayload)).\(parts[2])"
        license.activate(code: tampered)
        precondition(license.activatedLicenseCode.isEmpty)
        license.activate(code: try makeToken(privateKey, device: UUID().uuidString, email: email))
        precondition(license.activatedLicenseCode.isEmpty)
        license.activate(code: try makeToken(try makeKey(), device: device, email: email))
        precondition(license.activatedLicenseCode.isEmpty)
        let wrapped = stride(from: 0, to: token.count, by: 64).map { index -> String in
            let start = token.index(token.startIndex, offsetBy: index)
            let end = token.index(start, offsetBy: min(64, token.count - index))
            return String(token[start..<end])
        }.joined(separator: " \n")
        license.activate(code: "\n\t" + wrapped + "\n")
        precondition(license.isUnlocked && license.activatedLicenseCode == token)
        precondition(dockDefaults.double(forKey: "autohide-delay") == 1000,
                     "Activation must re-enable taskbar Dock handling")
        now = beginning.addingTimeInterval(30 * 24 * 3600)
        let restarted = LicenseService(
            keychainService: service, defaults: defaults, clock: { now }, testingPublicKeyPEM: pem)
        restarted.start(scheduleTimer: false)
        precondition(restarted.deviceID == device && restarted.isUnlocked)
        precondition(restarted.activatedLicenseCode == token)
        precondition(restarted.pendingBuyerEmail == email)
        precondition(restarted.purchaseRequestMailURL == nil,
                     "A restart must require choosing a payment provider before creating a new request")
        let betaServiceName = service + ".beta"
        let betaSuite = suite + ".beta"
        let betaDefaults = UserDefaults(suiteName: betaSuite)!
        defer {
            SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: betaServiceName] as CFDictionary)
            betaDefaults.removePersistentDomain(forName: betaSuite)
        }
        var betaNow = beginning
        let beta = LicenseService(keychainService: betaServiceName, defaults: betaDefaults,
            clock: { betaNow }, testingPublicKeyPEM: pem)
        beta.start(scheduleTimer: false)
        betaNow = beginning.addingTimeInterval(8 * 24 * 3600)
        beta.refreshStatus()
        precondition(!beta.isUnlocked)
        let fixture = "abcd–efgh–jklm"
        let fixtureHashURL = TaskDockLicenseResources.url(name: BetaCode.shortCodeHashesResource, ext: "txt")!
        let betaIdentifier = try BetaCode.identifier(in: fixture, publicKeyPEM: "",
            shortCodeHashes: BetaCode.shortCodeHashes(from: String(contentsOf: fixtureHashURL)))
        betaDefaults.set([betaIdentifier], forKey: "taskdock.trial.redeemedCodeIDs.v1")
        precondition(!beta.activate(code: fixture).isSuccess, "Legacy redeemed codes must remain spent")
        betaDefaults.removeObject(forKey: "taskdock.trial.redeemedCodeIDs.v1")
        precondition(!beta.activate(code: "not-a-code").isSuccess)
        let betaResult = beta.activate(code: fixture)
        precondition(betaResult.isSuccess && betaResult.message.contains("7 天"))
        precondition(beta.isUnlocked && beta.remainingDays == 7 && beta.activatedLicenseCode.isEmpty)
        let betaRestart = LicenseService(keychainService: betaServiceName, defaults: betaDefaults,
            clock: { betaNow }, testingPublicKeyPEM: pem)
        betaRestart.start(scheduleTimer: false)
        precondition(betaRestart.isUnlocked && betaRestart.remainingDays == 7)
        let duplicate = betaRestart.activate(code: fixture)
        precondition(!duplicate.isSuccess && duplicate.message.contains("已经"))
        betaNow = beginning.addingTimeInterval(15 * 24 * 3600)
        betaRestart.refreshStatus()
        precondition(!betaRestart.isUnlocked && betaRestart.activatedLicenseCode.isEmpty)
        precondition(!license.activate(code: fixture).isSuccess, "Purchased licenses do not consume trial codes")
        precondition(betaRestart.activate(code: "whosyourdaddy").isSuccess)
        betaNow = beginning.addingTimeInterval(30 * 365 * 24 * 3600)
        let permanentRestart = LicenseService(keychainService: betaServiceName, defaults: betaDefaults,
            clock: { betaNow }, testingPublicKeyPEM: pem)
        permanentRestart.start(scheduleTimer: false)
        precondition(permanentRestart.hasPermanentTrial && permanentRestart.isUnlocked)
        precondition(permanentRestart.activatedLicenseCode.isEmpty)
        print("PERMANENT_TRIAL_OK expired-trial restart long-term no-purchase-token")
        print("BETA_COMPAT_OK invalid legacy-duplicate unicode-dashes seven-days restart expiry no-paid-entitlement")
        print("OFFLINE_LICENSE_OK trial-boundary rollback dock-restore mail-content no-send tamper other-device wrong-key multiline restart")
    }

    private static func makeKey() throws -> SecKey {
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey([
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048
        ] as CFDictionary, &error) else { throw error!.takeRetainedValue() }
        return key
    }

    private static func makeToken(_ key: SecKey, device: String, email: String) throws -> String {
        let header = try JSONSerialization.data(withJSONObject: ["alg": "RS256", "typ": "JWT"], options: [.sortedKeys])
        let payload = try JSONSerialization.data(withJSONObject: [
            "iss": "taskdock-offline", "version": 1, "product": "taskdock", "tier": "perpetual",
            "device_id": device, "email": email, "issued_at": "2026-10-17T00:00:00Z",
            "license_id": UUID().uuidString
        ], options: [.sortedKeys])
        let signing = "\(base64URL(header)).\(base64URL(payload))"
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            key, .rsaSignatureMessagePKCS1v15SHA256, Data(signing.utf8) as CFData, &error) as Data? else {
            throw error!.takeRetainedValue()
        }
        return "\(signing).\(base64URL(signature))"
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    private static func normalizedBase64(_ string: String) -> String {
        var value = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        value += String(repeating: "=", count: (4 - value.count % 4) % 4)
        return value
    }
}
