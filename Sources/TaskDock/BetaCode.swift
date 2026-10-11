import CryptoKit
import Foundation

enum BetaCodeError: LocalizedError {
    case invalidCode
    case alreadyUsed
    case unavailable

    var errorDescription: String? {
        switch self {
        case .invalidCode: return "激活码无效，请检查是否完整复制。"
        case .alreadyUsed: return "这个激活码已经在此安装中使用过。"
        case .unavailable: return "内测验证信息缺失，请安装最新版本的 TaskDock。"
        }
    }
}

enum BetaCode {
    static let publicKeyResource = "TaskDockBetaPublicKey"
    static let shortCodeHashesResource = "TaskDockBetaCodeHashes"
    private static let alphabet = Set("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    static func shortCodeHashes(from text: String) -> Set<String> {
        Set(text.split(whereSeparator: \.isNewline).map(String.init))
    }

    /// Short codes are checked against the preloaded hash pool. Earlier signed codes remain valid.
    static func identifier(
        in rawCode: String,
        publicKeyPEM: String,
        shortCodeHashes: Set<String> = []
    ) throws -> String {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if !code.contains(".") {
            let normalized = code.uppercased().filter { $0 != "-" && !$0.isWhitespace }
            guard normalized.count == 12,
                  normalized.allSatisfy({ alphabet.contains($0) }) else {
                throw BetaCodeError.invalidCode
            }
            let digest = SHA256.hash(data: Data(normalized.utf8))
                .map { String(format: "%02x", $0) }.joined()
            guard shortCodeHashes.contains(digest) else { throw BetaCodeError.invalidCode }
            return "short:\(digest)"
        }
        let pieces = code.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 3, pieces[0] == "TD7",
              let payload = decodeURLBase64(String(pieces[1])), payload.count == 17,
              payload.first == 1,
              let signatureData = decodeURLBase64(String(pieces[2])),
              let signature = try? P256.Signing.ECDSASignature(derRepresentation: signatureData),
              let publicKey = try? P256.Signing.PublicKey(pemRepresentation: publicKeyPEM),
              publicKey.isValidSignature(signature, for: payload) else {
            throw BetaCodeError.invalidCode
        }
        return payload.dropFirst().map { String(format: "%02x", $0) }.joined()
    }

    private static func decodeURLBase64(_ value: String) -> Data? {
        var encoded = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        return Data(base64Encoded: encoded)
    }
}
