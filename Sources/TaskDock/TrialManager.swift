import Foundation

/// A reminder-only trial. It does not prevent use after expiration.
struct TrialManager {
    static let trialLength: TimeInterval = 7 * 24 * 60 * 60
    static let reminderInterval = 10

    private let defaults: UserDefaults
    private let firstUseKey = "taskdock.trial.firstUse.v1"
    private let latestSeenKey = "taskdock.trial.latestSeen.v1"
    private let expiredOperationCountKey = "taskdock.trial.expiredOperations.v1"

    init(defaults: UserDefaults = .standard, now: Date = Date()) {
        self.defaults = defaults
        if defaults.object(forKey: firstUseKey) == nil {
            defaults.set(now, forKey: firstUseKey)
        }
        if defaults.object(forKey: latestSeenKey) == nil {
            defaults.set(now, forKey: latestSeenKey)
        }
    }

    var firstUseDate: Date {
        defaults.object(forKey: firstUseKey) as? Date ?? Date()
    }

    func isExpired(at now: Date = Date()) -> Bool {
        let latestSeen = defaults.object(forKey: latestSeenKey) as? Date ?? now
        return max(now, latestSeen).timeIntervalSince(firstUseDate) >= Self.trialLength
    }

    /// Returns true exactly on each tenth taskbar action after trial expiry.
    func recordOperation(at now: Date = Date()) -> Bool {
        let latestSeen = defaults.object(forKey: latestSeenKey) as? Date ?? now
        let effectiveNow = max(now, latestSeen)
        defaults.set(effectiveNow, forKey: latestSeenKey)
        guard effectiveNow.timeIntervalSince(firstUseDate) >= Self.trialLength else { return false }
        let count = defaults.integer(forKey: expiredOperationCountKey) + 1
        defaults.set(count, forKey: expiredOperationCountKey)
        return count % Self.reminderInterval == 0
    }
}
