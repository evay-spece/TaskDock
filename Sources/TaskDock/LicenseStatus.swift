import CryptoKit
import Foundation
import Security

/// Reads the signed purchase entitlement used by TaskDock's activation flow.
/// An activation code or cached token alone is not proof of purchase.
enum LicenseStatus {
    private struct Entitlement: Decodable {
        let version: Int
        let issuer: String
        let audience: String
        let status: String
        let deviceId: String
        let issuedAt: Date
        let validUntil: Date
    }

    static var hasValidPurchase: Bool {
        guard let deviceId = keychainValue(account: "device-id"),
              let token = keychainValue(account: "license-token"),
              let path = Bundle.main.path(forResource: "TaskDockLicensePublicKey", ofType: "pem"),
              let pem = try? String(contentsOfFile: path, encoding: .utf8),
              let publicKey = try? P256.Signing.PublicKey(pemRepresentation: pem) else {
            return false
        }

        let pieces = token.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 2,
              let payload = base64URLData(String(pieces[0])),
              let signatureData = base64URLData(String(pieces[1])),
              let signature = try? P256.Signing.ECDSASignature(derRepresentation: signatureData),
              publicKey.isValidSignature(signature, for: Data(pieces[0].utf8)) else {
            return false
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) { return date }
            let plain = ISO8601DateFormatter()
            guard let date = plain.date(from: value) else {
                throw DecodingError.dataCorruptedError(
                    in: try decoder.singleValueContainer(), debugDescription: "Invalid timestamp"
                )
            }
            return date
        }
        guard let entitlement = try? decoder.decode(Entitlement.self, from: payload) else { return false }
        let now = Date()
        return entitlement.version == 1 &&
            entitlement.issuer == "taskdock-license" &&
            entitlement.audience == "com.taskdock.app" &&
            entitlement.status == "lifetime" &&
            entitlement.deviceId == deviceId &&
            entitlement.issuedAt <= now.addingTimeInterval(300) &&
            entitlement.validUntil > now
    }

    private static func keychainValue(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.taskdock.app.license.v1",
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func base64URLData(_ value: String) -> Data? {
        var encoded = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        return Data(base64Encoded: encoded)
    }
}
