import Foundation

public enum BrowserBridgeRegistration {
    public static func manifestURL(browser: ProgressBrowser, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Application Support/\(browser.supportDirectory)/NativeMessagingHosts/\(BrowserBridgeIdentity.hostName).json")
    }
    @discardableResult
    public static func register(browser: ProgressBrowser, executable: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> URL {
        guard executable.path.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: executable.path) else { throw BrowserBridgeError.missingComponent }
        let target = manifestURL(browser: browser, home: home)
        let fm = FileManager.default
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: target.path) {
            guard (try fm.attributesOfItem(atPath: target.path))[.type] as? FileAttributeType == .typeRegular else { throw BrowserBridgeError.unsafePath }
            let backup = target.appendingPathExtension("backup-" + UUID().uuidString)
            try fm.copyItem(at: target, to: backup)
        }
        let object: [String: Any] = ["name": BrowserBridgeIdentity.hostName, "description": "TaskDock 本机下载进度", "path": executable.path, "type": "stdio", "allowed_origins": [BrowserBridgeIdentity.origin]]
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: target, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        return target
    }
    public static func unregister(browser: ProgressBrowser, executable: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) throws {
        let target = manifestURL(browser: browser, home: home)
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        guard let object = try JSONSerialization.jsonObject(with: Data(contentsOf: target)) as? [String: Any],
              object["name"] as? String == BrowserBridgeIdentity.hostName,
              object["path"] as? String == executable.path else { throw BrowserBridgeError.unsafePath }
        try FileManager.default.removeItem(at: target)
    }
}
