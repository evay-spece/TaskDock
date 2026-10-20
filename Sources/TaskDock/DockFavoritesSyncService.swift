import AppKit
import ApplicationServices

/// Mirrors the persistent (pinned) Dock tiles. Recent apps, Trash, and unknown tile
/// types stay owned by the system Dock and are left untouched when writing.
@MainActor
final class DockFavoritesSyncService {
    struct Snapshot: Equatable {
        var apps: [FavoriteApp]
        var folders: [FavoriteFolder]
    }

    enum SyncError: LocalizedError {
        case unavailable
        case invalidApplication(String)
        case invalidFolder(String)
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .unavailable: return "无法读取系统 Dock 的固定项目。"
            case .invalidApplication(let name): return "无法将“\(name)”加入系统 Dock：找不到应用程序。"
            case .invalidFolder(let name): return "无法将“\(name)”加入系统 Dock：文件夹不存在。"
            case .writeFailed: return "系统 Dock 未接受收藏变更，请稍后重试。"
            }
        }
    }

    private let defaults: UserDefaults
    private let restartsDock: Bool
    private var pendingDockRestart: DispatchWorkItem?
    private static let finderID = "com.apple.finder"

    init(domain: String = "com.apple.dock", restartsDock: Bool = true) {
        defaults = UserDefaults(suiteName: domain) ?? .standard
        self.restartsDock = restartsDock
    }

    func read() throws -> Snapshot {
        defaults.synchronize()
        guard let appTiles = defaults.array(forKey: "persistent-apps") as? [[String: Any]],
              let otherTiles = defaults.array(forKey: "persistent-others") as? [[String: Any]] else {
            throw SyncError.unavailable
        }
        var apps = [finderFavorite()]
        var seenApps: Set<String> = [Self.finderID]
        for tile in appTiles where tile["tile-type"] as? String == "file-tile" {
            guard let url = Self.tileURL(tile), url.pathExtension.lowercased() == "app" else { continue }
            let bundle = Bundle(url: url)
            let bundleID = (tile["tile-data"] as? [String: Any])?["bundle-identifier"] as? String
                ?? bundle?.bundleIdentifier
            let name = (tile["tile-data"] as? [String: Any])?["file-label"] as? String
                ?? url.deletingPathExtension().lastPathComponent
            let id = bundleID ?? "name:\(name)"
            if seenApps.insert(id).inserted {
                apps.append(FavoriteApp(id: id, bundleIdentifier: bundleID,
                                        applicationName: name, bundlePath: url.path))
            }
        }
        var folders: [FavoriteFolder] = []
        var seenPaths: Set<String> = []
        for tile in otherTiles where tile["tile-type"] as? String == "directory-tile" {
            guard let url = Self.tileURL(tile) else { continue }
            let path = url.standardizedFileURL.path
            if seenPaths.insert(path).inserted { folders.append(FavoriteFolder(path: path)) }
        }
        return Snapshot(apps: apps, folders: folders)
    }

    /// Reads the app tiles currently visible in the native Dock, including
    /// running and recent apps that do not belong to its persistent app list.
    /// Returns nil while the Dock is restarting so callers retain their last view.
    func visibleUnpinnedApps(pinnedApps: [FavoriteApp]) -> [FavoriteApp]? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first,
              let dockList = Self.findDockList(in: AXUIElementCreateApplication(dock.processIdentifier), depth: 6),
              let children = Self.axValue(dockList, kAXChildrenAttribute) as? [AXUIElement] else {
            return nil
        }
        let pinnedIDs = Set(pinnedApps.map(\.id))
        let pinnedPaths = Set(pinnedApps.compactMap(\.bundlePath).map {
            URL(fileURLWithPath: $0).standardizedFileURL.path
        })
        var seen: Set<String> = []
        var result: [FavoriteApp] = []
        for item in children {
            guard Self.axValue(item, kAXSubroleAttribute) as? String == "AXApplicationDockItem",
                  let rawURL = Self.axValue(item, kAXURLAttribute),
                  let url = (rawURL as? URL) ?? (rawURL as? String).flatMap(URL.init(string:)),
                  url.pathExtension.lowercased() == "app" else { continue }
            let path = url.standardizedFileURL.path
            let bundleID = Bundle(url: url)?.bundleIdentifier
            let name = (Self.axValue(item, kAXTitleAttribute) as? String)
                ?? url.deletingPathExtension().lastPathComponent
            let id = bundleID ?? "name:\(name)"
            guard id != "com.taskdock.app", !pinnedIDs.contains(id), !pinnedPaths.contains(path),
                  seen.insert(id).inserted else { continue }
            result.append(FavoriteApp(id: id, bundleIdentifier: bundleID,
                                      applicationName: name, bundlePath: path))
        }
        return result
    }

    func write(_ desired: Snapshot) throws -> Snapshot {
        defaults.synchronize()
        guard let existingApps = defaults.array(forKey: "persistent-apps") as? [[String: Any]],
              let existingOthers = defaults.array(forKey: "persistent-others") as? [[String: Any]] else {
            throw SyncError.unavailable
        }
        let requestedApps = desired.apps.filter { $0.bundleIdentifier != Self.finderID && $0.id != Self.finderID }
        var appTiles: [[String: Any]] = []
        for app in requestedApps {
            if let existing = existingApps.first(where: { Self.matches($0, app: app) }) {
                appTiles.append(existing)
            } else {
                guard let url = app.bundleIdentifier.flatMap({ NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) })
                        ?? app.bundlePath.map(URL.init(fileURLWithPath:)),
                      FileManager.default.fileExists(atPath: url.path) else {
                    throw SyncError.invalidApplication(app.applicationName)
                }
                appTiles.append(Self.newTile(url: url, name: app.applicationName,
                                             type: "file-tile", bundleID: app.bundleIdentifier))
            }
        }
        var folderTiles: [[String: Any]] = []
        for folder in desired.folders {
            if let existing = existingOthers.first(where: { Self.tileURL($0)?.standardizedFileURL.path == folder.path
                && $0["tile-type"] as? String == "directory-tile" }) {
                folderTiles.append(existing)
            } else {
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
                      isDirectory.boolValue else { throw SyncError.invalidFolder(folder.name) }
                folderTiles.append(Self.newTile(url: folder.url, name: folder.name,
                                                type: "directory-tile", bundleID: nil))
            }
        }
        let mergedApps = Self.replaceManaged(in: existingApps, with: appTiles) {
            $0["tile-type"] as? String == "file-tile" && Self.tileURL($0)?.pathExtension.lowercased() == "app"
        }
        let mergedOthers = Self.replaceManaged(in: existingOthers, with: folderTiles) {
            $0["tile-type"] as? String == "directory-tile"
        }
        defaults.set(mergedApps, forKey: "persistent-apps")
        defaults.set(mergedOthers, forKey: "persistent-others")
        guard defaults.synchronize(),
              let savedApps = defaults.array(forKey: "persistent-apps") as? [[String: Any]],
              let savedOthers = defaults.array(forKey: "persistent-others") as? [[String: Any]],
              savedApps.count == mergedApps.count, savedOthers.count == mergedOthers.count else {
            throw SyncError.writeFailed
        }
        if restartsDock { scheduleDockRestart() }
        return try read()
    }

    private func scheduleDockRestart() {
        // A drag followed by another quick edit must produce one restart. Restarting
        // twice before the new Dock has loaded can restore its previous tile list.
        pendingDockRestart?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pendingDockRestart = nil
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            process.arguments = ["-9", "Dock"]
            try? process.run()
        }
        pendingDockRestart = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }

    private static func tileURL(_ tile: [String: Any]) -> URL? {
        guard let data = tile["tile-data"] as? [String: Any],
              let fileData = data["file-data"] as? [String: Any],
              let raw = fileData["_CFURLString"] as? String else { return nil }
        return URL(string: raw)?.standardizedFileURL
    }

    private static func findDockList(in element: AXUIElement, depth: Int) -> AXUIElement? {
        if axValue(element, kAXRoleAttribute) as? String == kAXListRole { return element }
        guard depth > 0,
              let children = axValue(element, kAXChildrenAttribute) as? [AXUIElement] else { return nil }
        for child in children {
            if let list = findDockList(in: child, depth: depth - 1) { return list }
        }
        return nil
    }

    private static func axValue(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as AnyObject?
    }

    private static func matches(_ tile: [String: Any], app: FavoriteApp) -> Bool {
        guard tile["tile-type"] as? String == "file-tile" else { return false }
        let data = tile["tile-data"] as? [String: Any]
        if let id = app.bundleIdentifier, data?["bundle-identifier"] as? String == id { return true }
        return tileURL(tile)?.path == app.bundlePath
    }

    private static func replaceManaged(in existing: [[String: Any]], with desired: [[String: Any]],
                                       isManaged: ([String: Any]) -> Bool) -> [[String: Any]] {
        var result: [[String: Any]] = []
        var index = 0
        for tile in existing {
            if isManaged(tile) {
                if index < desired.count { result.append(desired[index]); index += 1 }
            } else {
                result.append(tile)
            }
        }
        if index < desired.count { result.append(contentsOf: desired[index...]) }
        return result
    }

    private static func newTile(url: URL, name: String, type: String, bundleID: String?) -> [String: Any] {
        var tileData: [String: Any] = [
            "file-data": ["_CFURLString": url.absoluteString, "_CFURLStringType": 15],
            "file-label": name,
            "file-type": type == "directory-tile" ? 2 : 41
        ]
        if let bookmark = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil,
                                                relativeTo: nil) { tileData["book"] = bookmark }
        if let bundleID { tileData["bundle-identifier"] = bundleID }
        if type == "directory-tile" {
            tileData["arrangement"] = 1
            tileData["displayas"] = 1
            tileData["showas"] = 2
            tileData["preferreditemsize"] = "-1"
        }
        return ["GUID": UInt32.random(in: 1...UInt32.max), "tile-data": tileData, "tile-type": type]
    }

    private func finderFavorite() -> FavoriteApp {
        FavoriteApp(id: Self.finderID, bundleIdentifier: Self.finderID,
                    applicationName: "Finder", bundlePath: "/System/Library/CoreServices/Finder.app")
    }
}
