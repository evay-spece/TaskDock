import Foundation
import Security

@main
@MainActor
struct PermanentTrialSelfTest {
    static func main() {
        let service = "com.taskdock.permanent-trial-selftest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: service)!
        defer {
            SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service] as CFDictionary)
            defaults.removePersistentDomain(forName: service)
        }
        var now = Date()
        let license = LicenseService(keychainService: service, defaults: defaults, clock: { now })
        license.start(scheduleTimer: false)
        now.addTimeInterval(8 * 24 * 3600)
        license.refreshStatus()
        precondition(!license.isUnlocked)
        precondition(license.activate(code: "whosyourdaddy").isSuccess)
        now.addTimeInterval(50 * 365 * 24 * 3600)
        let restarted = LicenseService(keychainService: service, defaults: defaults, clock: { now })
        restarted.start(scheduleTimer: false)
        precondition(restarted.isUnlocked && restarted.hasPermanentTrial)
        precondition(restarted.activatedLicenseCode.isEmpty)
        print("PERMANENT_TRIAL_OK expired-trial restart fifty-years no-purchase-token")
    }
}
