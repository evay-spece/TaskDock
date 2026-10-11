import CryptoKit
import Darwin
import Foundation

@main
struct BetaCodeIssuer {
    static func main() throws {
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/TaskDock/BetaCodes", isDirectory: true)
        let privateKeyURL = support.appendingPathComponent("issuer-private-key.pem")
        let publicKeyURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/TaskDockBetaPublicKey.pem")
        let poolURL = support.appendingPathComponent("short-code-pool.txt")
        let nextIndexURL = support.appendingPathComponent("short-code-next-index.txt")
        let hashesURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/TaskDockBetaCodeHashes.txt")
        guard let command = CommandLine.arguments.dropFirst().first else {
            print("用法：scripts/beta-code pool-init | issue | issue-long")
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
        case "pool-init":
            guard !FileManager.default.fileExists(atPath: poolURL.path),
                  !FileManager.default.fileExists(atPath: hashesURL.path) else {
                throw IssuerError.poolAlreadyExists
            }
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
            var codes = Set<String>()
            var generator = SystemRandomNumberGenerator()
            while codes.count < 1_000 {
                let raw = String((0..<12).map { _ in alphabet[Int.random(in: 0..<32, using: &generator)] })
                codes.insert(raw)
            }
            let ordered = codes.sorted()
            let formatted = ordered.map { String($0.prefix(4)) + "-" + $0.dropFirst(4).prefix(4) + "-" + $0.suffix(4) }
            try (formatted.joined(separator: "\n") + "\n")
                .write(to: poolURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: poolURL.path)
            try "0\n".write(to: nextIndexURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: nextIndexURL.path)
            let hashes = ordered.map { code in
                SHA256.hash(data: Data(code.utf8)).map { String(format: "%02x", $0) }.joined()
            }.sorted()
            try (hashes.joined(separator: "\n") + "\n")
                .write(to: hashesURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: hashesURL.path)
            print("已生成 1000 个短码；原码仅保存在 \(poolURL.path)")
        case "issue":
            guard FileManager.default.fileExists(atPath: poolURL.path) else {
                throw IssuerError.poolMissing
            }
            let descriptor = open(support.appendingPathComponent("issue.lock").path,
                                  O_CREAT | O_RDWR, mode_t(0o600))
            guard descriptor >= 0 else { throw IssuerError.lockFailed }
            defer { close(descriptor) }
            guard flock(descriptor, LOCK_EX) == 0 else { throw IssuerError.lockFailed }
            defer { flock(descriptor, LOCK_UN) }
            let codes = try String(contentsOf: poolURL, encoding: .utf8)
                .split(whereSeparator: \.isNewline).map(String.init)
            let rawIndex = try String(contentsOf: nextIndexURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let index = Int(rawIndex), index >= 0, index < codes.count else {
                throw IssuerError.poolExhausted
            }
            try "\(index + 1)\n".write(to: nextIndexURL, atomically: true, encoding: .utf8)
            print(codes[index])
        case "issue-long":
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
    case poolAlreadyExists
    case poolMissing
    case poolExhausted
    case lockFailed
    case unknownCommand

    var errorDescription: String? {
        switch self {
        case .keyAlreadyExists: return "发码私钥已存在；为避免旧激活码失效，不会覆盖。"
        case .poolAlreadyExists: return "短码池已存在；为避免已发码失效，不会覆盖。"
        case .poolMissing: return "短码池不存在，请先运行 pool-init。"
        case .poolExhausted: return "短码已发完，需要更新 App 中的码池。"
        case .lockFailed: return "发码记录暂时无法锁定，请稍后重试。"
        case .unknownCommand: return "只支持 pool-init、issue 或 issue-long。"
        }
    }
}
