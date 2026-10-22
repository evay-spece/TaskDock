import AppKit
import Foundation

struct ContextMenuProvider: Identifiable {
    enum Kind { case finder, service }
    let id: String
    let name: String
    let source: String
    let path: String
    let kind: Kind
    let state: String
    let disabled: Bool
    let serviceKey: String?
}

enum ContextMenuBackend {
    static let storage = UserDefaults(suiteName: "com.taskdock.context-menu-manager")!
    static let pbsDomain = "pbs" as CFString

    static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: timeout)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeout.cancel()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "ContextMenuManager", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "系统命令未完成，请重试或使用系统设置。"])
        }
        return String(decoding: data, as: UTF8.self)
    }

    static func appName(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let components = url.pathComponents
        if let index = components.firstIndex(where: { $0.hasSuffix(".app") }) {
            let app = URL(fileURLWithPath: NSString.path(withComponents: Array(components[...index])))
            let bundle = Bundle(url: app)
            return bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? app.deletingPathExtension().lastPathComponent
        }
        return url.deletingPathExtension().lastPathComponent
    }

    static func finderProviders(_ dump: String) -> [ContextMenuProvider] {
        let regex = try! NSRegularExpression(pattern: #"^\s*([+!\-= ?]?)\s*([^\s(]+)\([^)]*\)\s+[^\n]*?(/[^\n]+\.appex)\s*$"#,
                                            options: .anchorsMatchLines)
        let ns = dump as NSString
        return regex.matches(in: dump, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            let state = ns.substring(with: match.range(at: 1))
            let identifier = ns.substring(with: match.range(at: 2))
            let path = ns.substring(with: match.range(at: 3))
            guard !identifier.hasPrefix("com.apple."), identifier != "com.taskdock.app.finder" else { return nil }
            return ContextMenuProvider(id: "finder:" + identifier, name: appName(path), source: identifier,
                                       path: path, kind: .finder, state: state, disabled: state == "-", serviceKey: nil)
        }
    }

    static func serviceStatus() -> [String: [String: Any]] {
        CFPreferencesAppSynchronize(pbsDomain)
        return CFPreferencesCopyAppValue("NSServicesStatus" as CFString, pbsDomain) as? [String: [String: Any]] ?? [:]
    }

    static func serviceProviders(_ dump: String, status: [String: [String: Any]]) throws -> [ContextMenuProvider] {
        // pbs prints an NSDictionary description. NSUUID is NSData's debug description,
        // not an OpenStep plist value; it is irrelevant to service identity.
        let cleaned = dump.replacingOccurrences(of: #"NSUUID = \{[^\n]*\};"#, with: "", options: .regularExpression)
        guard let entries = try PropertyListSerialization.propertyList(from: Data(cleaned.utf8), options: [], format: nil) as? [[String: Any]] else {
            throw NSError(domain: "ContextMenuManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法读取系统服务列表。"])
        }
        var seen = Set<String>()
        return entries.compactMap { entry in
            guard let bundleID = entry["NSBundleIdentifier"] as? String,
                  !bundleID.hasPrefix("com.apple."), !bundleID.hasPrefix("com.taskdock."),
                  let path = entry["NSBundlePath"] as? String,
                  FileManager.default.fileExists(atPath: path),
                  let menu = entry["NSMenuItem"] as? [String: String],
                  let originalName = menu["default"],
                  let message = entry["NSMessage"] as? String else { return nil }
            let key = "\(bundleID) - \(originalName) - \(message)"
            guard seen.insert(key).inserted else { return nil }
            let modes = status[key]?["presentation_modes"] as? [String: Any]
            let enabled = (modes?["ContextMenu"] as? Bool) ?? (status[key]?["enabled_context_menu"] as? Bool) ?? true
            let language = Bundle.preferredLocalizations(from: Array(menu.keys), forPreferences: Locale.preferredLanguages).first
            let title = language.flatMap { menu[$0] } ?? menu["zh_CN"] ?? originalName
            return ContextMenuProvider(id: "service:" + key, name: title, source: appName(path), path: path,
                                       kind: .service, state: "", disabled: !enabled, serviceKey: key)
        }
    }

    static func scan() throws -> [ContextMenuProvider] {
        let finder = try run("/usr/bin/pluginkit", ["-m", "-v", "-p", "com.apple.FinderSync"])
        let services = try run("/System/Library/CoreServices/pbs", ["-dump"])
        return (finderProviders(finder) + (try serviceProviders(services, status: serviceStatus())))
            .sorted { $0.source.localizedStandardCompare($1.source) == .orderedAscending }
    }

    static func backupKey(_ item: ContextMenuProvider) -> String { "original:" + item.id }
    static func hasBackup(_ item: ContextMenuProvider) -> Bool { storage.object(forKey: backupKey(item)) != nil }

    static func setDisabled(_ disabled: Bool, item: ContextMenuProvider) throws {
        guard item.source != "com.taskdock.app.finder", !item.source.hasPrefix("com.apple.") else { return }
        switch item.kind {
        case .finder:
            if !hasBackup(item) { storage.set(item.state, forKey: backupKey(item)); storage.synchronize() }
            _ = try run("/usr/bin/pluginkit", ["-e", disabled ? "ignore" : "use", "-i", item.source])
            let actual = finderProviders(try run("/usr/bin/pluginkit", ["-m", "-v", "-p", "com.apple.FinderSync"]))
            guard let current = actual.first(where: { $0.id == item.id }), current.disabled == disabled else {
                throw NSError(domain: "ContextMenuManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "扩展状态尚未更新，请刷新列表确认。"])
            }
        case .service:
            guard let key = item.serviceKey else { return }
            var all = serviceStatus()
            let old = all[key] ?? [:]
            if !hasBackup(item) {
                var snapshot: [String: Any] = [:]
                snapshot["enabled_context_menu"] = old["enabled_context_menu"] ?? "absent"
                snapshot["ContextMenu"] = (old["presentation_modes"] as? [String: Any])?["ContextMenu"] ?? "absent"
                storage.set(snapshot, forKey: backupKey(item)); storage.synchronize()
            }
            all[key] = contextStatus(old, enabled: !disabled)
            try saveServices(all)
        }
    }

    static func contextStatus(_ original: [String: Any], enabled: Bool) -> [String: Any] {
        var value = original
        var modes = value["presentation_modes"] as? [String: Any] ?? [:]
        value["enabled_context_menu"] = enabled
        modes["ContextMenu"] = enabled
        value["presentation_modes"] = modes
        return value
    }

    static func restore(_ item: ContextMenuProvider) throws {
        guard hasBackup(item) else { return }
        switch item.kind {
        case .finder:
            let original = storage.string(forKey: backupKey(item)) ?? ""
            _ = try run("/usr/bin/pluginkit", ["-e", original == "-" ? "ignore" : ((original == "+" || original == "!") ? "use" : "default"), "-i", item.source])
        case .service:
            guard let key = item.serviceKey, let snapshot = storage.dictionary(forKey: backupKey(item)) else { return }
            var all = serviceStatus()
            var value = all[key] ?? [:]
            var modes = value["presentation_modes"] as? [String: Any] ?? [:]
            if let flag = snapshot["enabled_context_menu"] as? Bool { value["enabled_context_menu"] = flag }
            else { value.removeValue(forKey: "enabled_context_menu") }
            if let flag = snapshot["ContextMenu"] as? Bool { modes["ContextMenu"] = flag }
            else { modes.removeValue(forKey: "ContextMenu") }
            if modes.isEmpty { value.removeValue(forKey: "presentation_modes") } else { value["presentation_modes"] = modes }
            if value.isEmpty { all.removeValue(forKey: key) } else { all[key] = value }
            try saveServices(all)
        }
        storage.removeObject(forKey: backupKey(item)); storage.synchronize()
    }

    static func saveServices(_ status: [String: [String: Any]]) throws {
        CFPreferencesSetAppValue("NSServicesStatus" as CFString, status as CFDictionary, pbsDomain)
        guard CFPreferencesAppSynchronize(pbsDomain), NSDictionary(dictionary: serviceStatus()).isEqual(to: status) else {
            throw NSError(domain: "ContextMenuManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "服务菜单设置未能保存。"])
        }
        _ = try run("/System/Library/CoreServices/pbs", ["-update"])
    }
}

@MainActor
final class ContextMenuManager: ObservableObject {
    @Published var items: [ContextMenuProvider] = []
    @Published var busy = false
    @Published var message = ""
    @Published var scanned = false

    func refresh() { perform { try ContextMenuBackend.scan() } }
    func change(_ item: ContextMenuProvider, restore: Bool = false) {
        perform {
            if restore { try ContextMenuBackend.restore(item) }
            else { try ContextMenuBackend.setDisabled(!item.disabled, item: item) }
            return try ContextMenuBackend.scan()
        }
    }
    private func perform(_ operation: @escaping () throws -> [ContextMenuProvider]) {
        guard !busy else { return }
        busy = true
        message = ""
        Task {
            do {
                items = try await Task.detached(priority: .userInitiated) { try operation() }.value
                scanned = true
                message = "已读取系统状态。更改后请重新打开右键菜单；部分扩展需重新启动 Finder 才会生效。"
            } catch { message = error.localizedDescription }
            busy = false
        }
    }
}
