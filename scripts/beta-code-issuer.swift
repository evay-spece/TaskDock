import CryptoKit
import Foundation

@main
struct BetaCodeIssuer {
    static func main() throws {
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/TaskDock/BetaCodes", isDirectory: true)
        let privateKeyURL = support.appendingPathComponent("issuer-private-key.pem")
        let publicKeyURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/TaskDockBetaPublicKey.pem")
        guard let command = CommandLine.arguments.dropFirst().first else {
            print("用法：scripts/beta-code init | issue")
            return
        }
        switch command {
        case "init":
            guard !FileManager.default.fileExists(atPath: privateKeyURL.path) else {
                throw IssuerError.keyAlreadyExists
            }
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let key = P256.Signing.PrivateKey()
            try key.pemRepresentation.write(to: privateKeyURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: privateKeyURL.path)
            try key.publicKey.pemRepresentation.write(to: publicKeyURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: publicKeyURL.path)
            print("发码私钥：\(privateKeyURL.path)")
            print("App 公钥：\(publicKeyURL.path)")
        case "issue":
            let pem = try String(contentsOf: privateKeyURL, encoding: .utf8)
            let key = try P256.Signing.PrivateKey(pemRepresentation: pem)
            var payload = Data([1])
            payload.append(contentsOf: withUnsafeBytes(of: UUID().uuid) { Array($0) })
            let signature = try key.signature(for: payload)
            let code = "TD7.\(base64URL(payload)).\(base64URL(signature.derRepresentation))"
            print(code)
        default:
            throw IssuerError.unknownCommand
        }
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private enum IssuerError: LocalizedError {
    case keyAlreadyExists
    case unknownCommand

    var errorDescription: String? {
        switch self {
        case .keyAlreadyExists: return "发码私钥已存在；为避免旧激活码失效，不会覆盖。"
        case .unknownCommand: return "只支持 init 或 issue。"
        }
    }
}
