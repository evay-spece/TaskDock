import CryptoKit
import Foundation

struct PreparedUpdate {
    let appURL: URL
    let stagingRoot: URL
}

enum UpdateSupport {
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let candidateParts = versionParts(candidate)
        let currentParts = versionParts(current)
        let count = max(candidateParts.count, currentParts.count)
        for index in 0..<count {
            let lhs = index < candidateParts.count ? candidateParts[index] : 0
            let rhs = index < currentParts.count ? currentParts[index] : 0
            if lhs != rhs { return lhs > rhs }
        }
        return false
    }

    static func normalizedVersion(_ version: String) -> String {
        version.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    }

    static func prepareCandidate(
        archiveURL: URL,
        stagingRoot: URL,
        expectedVersion: String,
        expectedDigest: String,
        currentAppURL: URL
    ) throws -> PreparedUpdate {
        let expectedHash = expectedDigest
            .lowercased()
            .replacingOccurrences(of: "sha256:", with: "")
        guard expectedHash.count == 64,
              try sha256(of: archiveURL) == expectedHash else {
            throw UpdateFailure.invalidDigest
        }

        let extractionRoot = stagingRoot.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extractionRoot, withIntermediateDirectories: true)
        try run("/usr/bin/ditto", arguments: ["-x", "-k", archiveURL.path, extractionRoot.path])

        let candidateApp = extractionRoot.appendingPathComponent("TaskDock.app", isDirectory: true)
        guard let candidateBundle = Bundle(url: candidateApp),
              candidateBundle.bundleIdentifier == "com.taskdock.app",
              candidateBundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == expectedVersion else {
            throw UpdateFailure.invalidApplication
        }

        try run("/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", candidateApp.path])
        let executable = candidateApp.appendingPathComponent("Contents/MacOS/TaskDock")
        let architectures = try run("/usr/bin/lipo", arguments: ["-archs", executable.path])
        guard architectures.split(whereSeparator: \Character.isWhitespace).contains("arm64") else {
            throw UpdateFailure.unsupportedArchitecture
        }

        let currentTeam = try signingTeamIdentifier(for: currentAppURL)
        let candidateTeam = try signingTeamIdentifier(for: candidateApp)
        if let currentTeam, currentTeam != candidateTeam {
            throw UpdateFailure.signingIdentityMismatch
        }

        return PreparedUpdate(appURL: candidateApp, stagingRoot: stagingRoot)
    }

    static func launchInstaller(
        prepared: PreparedUpdate,
        currentAppURL: URL,
        currentProcessID: pid_t,
        relaunch: Bool = true
    ) throws {
        let parent = currentAppURL.deletingLastPathComponent()
        guard currentAppURL.pathExtension == "app",
              currentAppURL.lastPathComponent == "TaskDock.app",
              FileManager.default.isWritableFile(atPath: parent.path) else {
            throw UpdateFailure.installLocationNotWritable
        }

        let backup = parent.appendingPathComponent("TaskDock-update-backup-\(UUID().uuidString).app")
        let script = #"""
        current_app="$1"
        new_app="$2"
        old_pid="$3"
        staging_root="$4"
        backup_app="$5"
        should_relaunch="$6"

        for _ in {1..200}; do
          if ! /bin/kill -0 "$old_pid" 2>/dev/null; then break; fi
          /bin/sleep 0.05
        done
        if /bin/kill -0 "$old_pid" 2>/dev/null; then exit 10; fi

        /bin/mv "$current_app" "$backup_app" || exit 11
        if /bin/mv "$new_app" "$current_app" && { [[ "$should_relaunch" != "1" ]] || /usr/bin/open -n "$current_app"; }; then
          /bin/rm -rf "$backup_app" "$staging_root"
          exit 0
        fi

        /bin/rm -rf "$current_app"
        /bin/mv "$backup_app" "$current_app"
        /usr/bin/open -n "$current_app"
        exit 12
        """#

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            "-c", script, "taskdock-updater",
            currentAppURL.path,
            prepared.appURL.path,
            String(currentProcessID),
            prepared.stagingRoot.path,
            backup.path,
            relaunch ? "1" : "0"
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    private static func versionParts(_ version: String) -> [Int] {
        normalizedVersion(version)
            .split(separator: ".")
            .map { component in Int(component.prefix { $0.isNumber }) ?? 0 }
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func signingTeamIdentifier(for appURL: URL) throws -> String? {
        let output = try run("/usr/bin/codesign", arguments: ["-d", "--verbose=4", appURL.path])
        return output
            .split(separator: "\n")
            .first(where: { $0.hasPrefix("TeamIdentifier=") })
            .map { String($0.dropFirst("TeamIdentifier=".count)) }
            .flatMap { $0 == "not set" ? nil : $0 }
    }

    @discardableResult
    private static func run(_ executable: String, arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw UpdateFailure.commandFailed(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return text
    }
}

enum UpdateFailure: LocalizedError {
    case invalidDigest
    case invalidApplication
    case unsupportedArchitecture
    case signingIdentityMismatch
    case installLocationNotWritable
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidDigest: return "安装包校验失败，未进行更新"
        case .invalidApplication: return "安装包不是有效的 TaskDock"
        case .unsupportedArchitecture: return "安装包不支持当前 Mac"
        case .signingIdentityMismatch: return "安装包签名与当前版本不一致"
        case .installLocationNotWritable: return "TaskDock 所在位置不可写，请移到“应用程序”后重试"
        case .commandFailed: return "安装包验证失败，未进行更新"
        }
    }
}
