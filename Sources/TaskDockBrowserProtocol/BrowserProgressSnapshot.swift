import Foundation

public enum ProgressBrowser: String, Codable, CaseIterable {
    case chrome, edge, safari
    public static let bridgeBrowsers: [ProgressBrowser] = [.chrome, .edge]
    public var label: String {
        switch self {
        case .chrome: return "Chrome"
        case .edge: return "Edge"
        case .safari: return "Safari"
        }
    }
    public var bundleIdentifier: String {
        switch self {
        case .chrome: return "com.google.Chrome"
        case .edge: return "com.microsoft.edgemac"
        case .safari: return "com.apple.Safari"
        }
    }
    public var supportDirectory: String {
        switch self {
        case .chrome: return "Google/Chrome"
        case .edge: return "Microsoft Edge"
        case .safari: return "Safari"
        }
    }
}

public enum BrowserBridgeError: Error, LocalizedError {
    case invalidMessage, invalidOrigin, unsafePath, tooManyProfiles, missingComponent
    public var errorDescription: String? {
        switch self {
        case .missingComponent: return "本机组件缺失，请重新安装完整的 TaskDock。"
        case .unsafePath: return "目标路径不是可用的普通文件夹，未修改配置。"
        default: return "浏览器连接信息无效，未接收该信息。"
        }
    }
}

public struct BrowserProgressSnapshot: Codable {
    public let version: Int
    public let type: String
    public let browser: ProgressBrowser
    public let profile: String
    public let receivedBytes: Int64
    public let totalBytes: Int64
    public let activeCount: Int
    public let unknownCount: Int
    public let downloads: [BrowserDownloadRecord]?

    public static func parse(_ data: Data) throws -> Self {
        var keys: Set<String> = ["version", "type", "browser", "profile", "receivedBytes", "totalBytes", "activeCount", "unknownCount"]
        guard data.count <= 262144,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw BrowserBridgeError.invalidMessage }
        if [2, 3].contains(object["version"] as? Int ?? 0) { keys.insert("downloads") }
        guard Set(object.keys) == keys else { throw BrowserBridgeError.invalidMessage }
        let snapshot = try JSONDecoder().decode(Self.self, from: data)
        guard (1...3).contains(snapshot.version), snapshot.type == "snapshot", snapshot.browser != .safari,
              let uuid = UUID(uuidString: snapshot.profile), uuid.uuidString.lowercased() == snapshot.profile,
              snapshot.receivedBytes >= 0, snapshot.totalBytes >= snapshot.receivedBytes,
              snapshot.totalBytes <= 9_007_199_254_740_991,
              (0...10000).contains(snapshot.activeCount),
              (0...snapshot.activeCount).contains(snapshot.unknownCount),
              snapshot.activeCount != 0 || (snapshot.totalBytes == 0 && snapshot.unknownCount == 0),
              snapshot.totalBytes != 0 || snapshot.receivedBytes == 0,
              snapshot.totalBytes != 0 || snapshot.unknownCount == snapshot.activeCount,
              snapshot.totalBytes == 0 || snapshot.activeCount > snapshot.unknownCount else { throw BrowserBridgeError.invalidMessage }
        if snapshot.version >= 2 {
            guard let records = snapshot.downloads, records.count <= 128,
                  records.allSatisfy(\.isValid), Set(records.map(\.id)).count == records.count else { throw BrowserBridgeError.invalidMessage }
        }
        return snapshot
    }
}

public struct StoredBrowserProgress: Codable {
    public let snapshot: BrowserProgressSnapshot
    public let updatedAt: Date
    public let session: UUID
}

public struct BrowserProgressStore {
    public let directory: URL
    public init(directory: URL = defaultDirectory) { self.directory = directory }
    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/TaskDock/BrowserProgress", isDirectory: true)
    }
    private func ensureDirectory() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: directory.path) {
            let attributes = try fm.attributesOfItem(atPath: directory.path)
            guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw BrowserBridgeError.unsafePath }
        } else {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }
    private func url(_ snapshot: BrowserProgressSnapshot) -> URL {
        directory.appendingPathComponent("\(snapshot.browser.rawValue)-\(snapshot.profile).json")
    }
    public func save(_ snapshot: BrowserProgressSnapshot, session: UUID, now: Date = Date()) throws {
        try ensureDirectory()
        let target = url(snapshot)
        if !FileManager.default.fileExists(atPath: target.path),
           (try FileManager.default.contentsOfDirectory(atPath: directory.path)).count >= 128 {
            throw BrowserBridgeError.tooManyProfiles
        }
        // Browser heartbeats and reconnects must never extend a completed item's lifetime.
        let previous = (try? Data(contentsOf: target)).flatMap { try? JSONDecoder().decode(StoredBrowserProgress.self, from: $0) }
        var normalized = snapshot
        if let downloads = snapshot.downloads {
            var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as! [String: Any]
            object["downloads"] = try downloads.map { record -> [String: Any] in
                var fields = try JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as! [String: Any]
                if record.isComplete {
                    let prior = previous?.snapshot.downloads?.first { $0.id == record.id && $0.isComplete }
                    fields["completedAt"] = record.completedAt ?? prior?.completedAt ?? (prior != nil ? previous?.updatedAt.timeIntervalSince1970 : nil)
                        ?? now.timeIntervalSince1970
                }
                return fields
            }
            normalized = try BrowserProgressSnapshot.parse(JSONSerialization.data(withJSONObject: object))
        }
        let stored = StoredBrowserProgress(snapshot: normalized, updatedAt: now, session: session)
        try JSONEncoder().encode(stored).write(to: target, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
    }
    public func clear(_ snapshot: BrowserProgressSnapshot, session: UUID) {
        let target = url(snapshot)
        guard let data = try? Data(contentsOf: target),
              let stored = try? JSONDecoder().decode(StoredBrowserProgress.self, from: data), stored.session == session else { return }
        // Preserve completed downloads after browser exit. Active records still expire.
        guard let records = stored.snapshot.downloads?.filter({ $0.isComplete }), !records.isEmpty,
              let data = try? JSONEncoder().encode(stored.snapshot),
              var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            try? FileManager.default.removeItem(at: target); return
        }
        object["downloads"] = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(records))
        object["receivedBytes"] = 0; object["totalBytes"] = 0
        object["activeCount"] = 0; object["unknownCount"] = 0
        if let encoded = try? JSONSerialization.data(withJSONObject: object), let snapshot = try? BrowserProgressSnapshot.parse(encoded) {
            try? save(snapshot, session: session)
        }
    }
    public func tasks(now: Date = Date()) -> [BrowserDownloadTask] {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else { return [] }
        var tasks: [BrowserDownloadTask] = []
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).prefix(128) where url.pathExtension == "json" {
            guard let attributes = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  attributes.isRegularFile == true, (attributes.fileSize ?? 266241) <= 266240,
                  let data = try? Data(contentsOf: url),
                  let stored = try? JSONDecoder().decode(StoredBrowserProgress.self, from: data),
                  let validatedData = try? JSONEncoder().encode(stored.snapshot),
                  let snapshot = try? BrowserProgressSnapshot.parse(validatedData),
                  now.timeIntervalSince(stored.updatedAt) >= -2 else { continue }
            let records = (snapshot.downloads ?? []).filter {
                if $0.isComplete {
                    let finished = $0.completedAt ?? stored.updatedAt.timeIntervalSince1970
                    let age = now.timeIntervalSince1970 - finished
                    return age >= -2 && age < 30 * 60 && ($0.fileURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false)
                }
                return now.timeIntervalSince(stored.updatedAt) <= 15
            }
            tasks += records.map { BrowserDownloadTask(browser: snapshot.browser, profile: snapshot.profile, download: $0) }
        }
        return tasks
    }
    public func fraction(browser: ProgressBrowser, now: Date = Date()) -> Double? {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else { return nil }
        var received: Double = 0, total: Double = 0
        for url in urls.prefix(128) where url.lastPathComponent.hasPrefix(browser.rawValue + "-") && url.pathExtension == "json" {
            guard let attributes = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  attributes.isRegularFile == true, (attributes.fileSize ?? 266241) <= 266240,
                  let data = try? Data(contentsOf: url),
                  let stored = try? JSONDecoder().decode(StoredBrowserProgress.self, from: data),
                  let validatedData = try? JSONEncoder().encode(stored.snapshot),
                  let snapshot = try? BrowserProgressSnapshot.parse(validatedData), snapshot.browser == browser,
                  now.timeIntervalSince(stored.updatedAt) >= -2, now.timeIntervalSince(stored.updatedAt) <= 15,
                  snapshot.activeCount > 0, snapshot.totalBytes > 0 else { continue }
            received += Double(snapshot.receivedBytes)
            total += Double(snapshot.totalBytes)
        }
        guard total > 0 else { return nil }
        return min(0.999, max(0.001, received / total))
    }
}
