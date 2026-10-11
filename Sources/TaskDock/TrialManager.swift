import Foundation

/// Seven days from first launch, plus seven days for each distinct signed beta code.
struct TrialManager {
    static let trialLength: TimeInterval = 7 * 24 * 60 * 60

    private let defaults: UserDefaults
    private let firstUseKey = "taskdock.trial.firstUse.v1"
    private let latestSeenKey = "taskdock.trial.latestSeen.v1"
    private let extensionExpiryKey = "taskdock.trial.extensionExpiry.v1"
    private let redeemedCodeIDsKey = "taskdock.trial.redeemedCodeIDs.v1"

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

    var expiryDate: Date {
        let originalExpiry = firstUseDate.addingTimeInterval(Self.trialLength)
        let extendedExpiry = defaults.object(forKey: extensionExpiryKey) as? Date ?? originalExpiry
        return max(originalExpiry, extendedExpiry)
    }

    func remainingDays(at now: Date = Date()) -> Int {
        let latestSeen = defaults.object(forKey: latestSeenKey) as? Date ?? now
        return max(0, Int(ceil(expiryDate.timeIntervalSince(max(now, latestSeen)) / (24 * 60 * 60))))
    }

    func isExpired(at now: Date = Date()) -> Bool {
        let latestSeen = defaults.object(forKey: latestSeenKey) as? Date ?? now
        return max(now, latestSeen) >= expiryDate
    }

    func recordOperation(at now: Date = Date()) {
        let latestSeen = defaults.object(forKey: latestSeenKey) as? Date ?? now
        defaults.set(max(now, latestSeen), forKey: latestSeenKey)
    }

    @discardableResult
    func redeem(_ code: String, publicKeyPEM: String, at now: Date = Date()) throws -> Date {
        let identifier = try BetaCode.identifier(in: code, publicKeyPEM: publicKeyPEM)
        var redeemed = Set(defaults.stringArray(forKey: redeemedCodeIDsKey) ?? [])
        guard redeemed.insert(identifier).inserted else { throw BetaCodeError.alreadyUsed }
        let latestSeen = defaults.object(forKey: latestSeenKey) as? Date ?? now
        let effectiveNow = max(now, latestSeen)
        let extendedExpiry = max(expiryDate, effectiveNow).addingTimeInterval(Self.trialLength)
        defaults.set(extendedExpiry, forKey: extensionExpiryKey)
        defaults.set(redeemed.sorted(), forKey: redeemedCodeIDsKey)
        defaults.set(effectiveNow, forKey: latestSeenKey)
        return extendedExpiry
    }
}
