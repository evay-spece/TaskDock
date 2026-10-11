import CryptoKit
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
        trial.recordOperation(at: beforeExpiry)
        let expiry = start.addingTimeInterval(TrialManager.trialLength)
        precondition(trial.isExpired(at: expiry))
        let signingKey = P256.Signing.PrivateKey()
        let code = makeCode(signingKey)
        let extendedExpiry = try! trial.redeem(code, publicKeyPEM: signingKey.publicKey.pemRepresentation, at: expiry)
        precondition(extendedExpiry == expiry.addingTimeInterval(TrialManager.trialLength))
        precondition(!trial.isExpired(at: expiry))
        precondition(trial.remainingDays(at: expiry) == 7)
        precondition(trial.isExpired(at: extendedExpiry))
        do {
            _ = try trial.redeem(code, publicKeyPEM: signingKey.publicKey.pemRepresentation, at: expiry)
            preconditionFailure("same code must not add another week")
        } catch BetaCodeError.alreadyUsed {
        } catch {
            preconditionFailure("unexpected duplicate-code error: \(error)")
        }
        let invalidCode = code + "x"
        do {
            _ = try trial.redeem(invalidCode, publicKeyPEM: signingKey.publicKey.pemRepresentation, at: expiry)
            preconditionFailure("tampered code must fail")
        } catch BetaCodeError.invalidCode {
        } catch {
            preconditionFailure("unexpected invalid-code error: \(error)")
        }
        trial.recordOperation(at: extendedExpiry)
        precondition(trial.isExpired(at: start), "clock rollback must not renew trial")
        let reloaded = TrialManager(defaults: defaults, now: expiry)
        precondition(reloaded.firstUseDate == start)
        precondition(reloaded.expiryDate == extendedExpiry)
        let secondCode = makeCode(signingKey)
        precondition(try! reloaded.redeem(secondCode, publicKeyPEM: signingKey.publicKey.pemRepresentation,
                                         at: expiry.addingTimeInterval(3 * 86400)) ==
                     extendedExpiry.addingTimeInterval(TrialManager.trialLength))
        let shortCode = "ABCD-EFGH-JKLM"
        let shortDigest = SHA256.hash(data: Data("ABCDEFGHJKLM".utf8))
            .map { String(format: "%02x", $0) }.joined()
        let shortHashes: Set<String> = [shortDigest]
        let thirdExpiry = try! reloaded.redeem(shortCode, publicKeyPEM: signingKey.publicKey.pemRepresentation,
                                               shortCodeHashes: shortHashes, at: expiry)
        precondition(thirdExpiry == extendedExpiry.addingTimeInterval(2 * TrialManager.trialLength))
        do {
            _ = try reloaded.redeem(shortCode, publicKeyPEM: signingKey.publicKey.pemRepresentation,
                                    shortCodeHashes: shortHashes, at: expiry)
            preconditionFailure("same short code must not add another week")
        } catch BetaCodeError.alreadyUsed {
        } catch {
            preconditionFailure("unexpected duplicate short-code error: \(error)")
        }
        do {
            _ = try reloaded.redeem("ABCD-EFGH-JKLN", publicKeyPEM: signingKey.publicKey.pemRepresentation,
                                    shortCodeHashes: shortHashes, at: expiry)
            preconditionFailure("unknown short code must fail")
        } catch BetaCodeError.invalidCode {
        } catch {
            preconditionFailure("unexpected unknown short-code error: \(error)")
        }
        print("TRIAL_OK")
    }

    private static func makeCode(_ key: P256.Signing.PrivateKey) -> String {
        var payload = Data([1])
        payload.append(contentsOf: withUnsafeBytes(of: UUID().uuid) { Array($0) })
        let signature = try! key.signature(for: payload)
        func encoded(_ data: Data) -> String {
            data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return "TD7.\(encoded(payload)).\(encoded(signature.derRepresentation))"
    }
}
