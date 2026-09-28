import AppKit

/// Temporarily suppresses the native Dock without losing the user's Dock preferences.
@MainActor
final class SystemDockVisibilityController {
    private let domain = "com.apple.dock"
    private let snapshotKey = "taskdock.originalSystemDockPreferences"
    private var isApplied = false

    func synchronize(hidden: Bool) {
        guard let dockDefaults = UserDefaults(suiteName: domain) else { return }
        if hidden {
            guard !isApplied else { return }
            if UserDefaults.standard.dictionary(forKey: snapshotKey) == nil {
                let preferences = dockDefaults.persistentDomain(forName: domain) ?? [:]
                UserDefaults.standard.set([
                    "hadAutohide": preferences["autohide"] != nil,
                    "autohide": preferences["autohide"] ?? false,
                    "hadDelay": preferences["autohide-delay"] != nil,
                    "delay": preferences["autohide-delay"] ?? 0.0
                ], forKey: snapshotKey)
            }
            dockDefaults.set(true, forKey: "autohide")
            dockDefaults.set(1000.0, forKey: "autohide-delay")
            dockDefaults.synchronize()
            isApplied = true
            restartDock()
        } else {
            restore()
        }
    }

    func restore() {
        guard let snapshot = UserDefaults.standard.dictionary(forKey: snapshotKey),
              let dockDefaults = UserDefaults(suiteName: domain) else { return }
        if snapshot["hadAutohide"] as? Bool == true {
            dockDefaults.set(snapshot["autohide"], forKey: "autohide")
        } else {
            dockDefaults.removeObject(forKey: "autohide")
        }
        if snapshot["hadDelay"] as? Bool == true {
            dockDefaults.set(snapshot["delay"], forKey: "autohide-delay")
        } else {
            dockDefaults.removeObject(forKey: "autohide-delay")
        }
        dockDefaults.synchronize()
        UserDefaults.standard.removeObject(forKey: snapshotKey)
        isApplied = false
        restartDock()
    }

    private func restartDock() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Dock"]
        try? process.run()
    }
}
