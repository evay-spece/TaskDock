import Foundation
import Security

enum OfflineLicenseVerifier {
    static func verify(token: String, deviceID: String, pem: String) -> Bool {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let headerData = Data(base64URL: String(parts[0])),
              let payloadData = Data(base64URL: String(parts[1])),
              let signature = Data(base64URL: String(parts[2])),
              let header = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any],
              header["alg"] as? String == "RS256",
              let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              payload["iss"] as? String == "taskdock-offline",
              payload["version"] as? Int == 1,
              payload["product"] as? String == "taskdock",
              payload["tier"] as? String == "perpetual",
              payload["device_id"] as? String == deviceID else { return false }

        let encodedKey = pem
            .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----BEGIN RSA PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END RSA PUBLIC KEY-----", with: "")
            .components(separatedBy: .whitespacesAndNewlines).joined()
        guard let keyData = Data(base64Encoded: encodedKey) else { return false }
        var error: Unmanaged<CFError>?
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: 2048,
        ]
        guard let publicKey = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &error) else { return false }
        let signingInput = Data("\(parts[0]).\(parts[1])".utf8)
        return SecKeyVerifySignature(publicKey, .rsaSignatureMessagePKCS1v15SHA256,
                                     signingInput as CFData, signature as CFData, &error)
    }
}

private extension Data {
    init?(base64URL value: String) {
        var normalized = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let remainder = normalized.count % 4
        if remainder != 0 { normalized += String(repeating: "=", count: 4 - remainder) }
        self.init(base64Encoded: normalized)
    }
}
