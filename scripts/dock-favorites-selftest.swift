import AppKit

struct FavoriteApp: Identifiable, Codable, Hashable {
    let id: String
    let bundleIdentifier: String?
    let applicationName: String
    let bundlePath: String?
}

struct FavoriteFolder: Identifiable, Codable, Hashable {
    let path: String
    var id: String { path }
    var name: String { FileManager.default.displayName(atPath: path) }
    var url: URL { URL(fileURLWithPath: path, isDirectory: true) }
}

@main @MainActor
struct DockFavoritesSelfTest {
    static func main() throws {
        let domain = "taskdock.dock-sync.selftest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let safari = URL(fileURLWithPath: "/System/Applications/Safari.app")
        let notes = URL(fileURLWithPath: "/System/Applications/Notes.app")
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        func tile(_ url: URL, _ type: String, _ id: String? = nil) -> [String: Any] {
            var data: [String: Any] = ["file-data": ["_CFURLString": url.absoluteString, "_CFURLStringType": 15],
                                       "file-label": url.lastPathComponent]
            if let id { data["bundle-identifier"] = id }
            return ["tile-type": type, "tile-data": data, "GUID": 1]
        }
        let spacer: [String: Any] = ["tile-type": "small-spacer-tile", "GUID": 99]
        let file: [String: Any] = ["tile-type": "file-tile", "GUID": 98,
                                   "tile-data": ["file-data": ["_CFURLString": "file:///tmp/document.txt", "_CFURLStringType": 15]]]
        defaults.set([tile(safari, "file-tile", "com.apple.Safari"), spacer], forKey: "persistent-apps")
        defaults.set([tile(downloads, "directory-tile"), file], forKey: "persistent-others")
        let sync = DockFavoritesSyncService(domain: domain, restartsDock: false)
        let original = try sync.read()
        precondition(original.apps.map(\.id) == ["com.apple.finder", "com.apple.Safari"])
        precondition(original.folders.map(\.path) == [downloads.path])
        let added = FavoriteApp(id: "com.apple.Notes", bundleIdentifier: "com.apple.Notes",
                                applicationName: "Notes", bundlePath: notes.path)
        let updated = try sync.write(.init(apps: [original.apps[0], added, original.apps[1]], folders: []))
        precondition(updated.apps.map(\.id) == ["com.apple.finder", "com.apple.Notes", "com.apple.Safari"])
        precondition(updated.folders.isEmpty)
        let savedApps = defaults.array(forKey: "persistent-apps") as! [[String: Any]]
        let savedOthers = defaults.array(forKey: "persistent-others") as! [[String: Any]]
        precondition(savedApps.contains { $0["GUID"] as? Int == 99 })
        precondition(savedOthers.contains { $0["GUID"] as? Int == 98 })
        print("DOCK_FAVORITES_SYNC_OK")
    }
}
