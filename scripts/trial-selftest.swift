import Foundation

@main
struct TrialSelfTest {
    static func main() {
        let suite = "taskdock.trial.selftest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let trial = TrialManager(defaults: defaults, now: start)
        let beforeExpiry = start.addingTimeInterval(TrialManager.trialLength - 1)
        precondition(!trial.isExpired(at: beforeExpiry))
        precondition(!trial.recordOperation(at: beforeExpiry))
        let expiry = start.addingTimeInterval(TrialManager.trialLength)
        precondition(trial.isExpired(at: expiry))
        for index in 1...30 {
            precondition(trial.recordOperation(at: expiry) == (index % 10 == 0),
                         "reminder boundary \(index)")
        }
        precondition(trial.isExpired(at: start), "clock rollback must not renew trial")
        let reloaded = TrialManager(defaults: defaults, now: expiry)
        precondition(reloaded.firstUseDate == start)
        precondition(!reloaded.recordOperation(at: expiry))
        print("TRIAL_OK")
    }
}
