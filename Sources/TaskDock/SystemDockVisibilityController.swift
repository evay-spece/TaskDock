import AppKit

/// Temporarily suppresses the native Dock without losing the user's Dock preferences.
@MainActor
final class SystemDockVisibilityController {
    private let domain: String
    private let dockDefaults: UserDefaults?
    private let snapshotDefaults: UserDefaults
    private let restartDockAction: () -> Void
    private let snapshotKey = "taskdock.originalSystemDockPreferences"
    private var appliedHidden: Bool?

    init(
        domain: String = "com.apple.dock",
        dockDefaults: UserDefaults? = UserDefaults(suiteName: "com.apple.dock"),
        snapshotDefaults: UserDefaults = .standard,
        restartDock: (() -> Void)? = nil
    ) {
        self.domain = domain
        self.dockDefaults = dockDefaults
        self.snapshotDefaults = snapshotDefaults
        restartDockAction = restartDock ?? Self.restartSystemDock
    }

    func synchronize(hidden: Bool) {
        guard let dockDefaults, appliedHidden != hidden else { return }
        let preferences = dockDefaults.persistentDomain(forName: domain) ?? [:]
        let autohideMatches = (preferences["autohide"] as? Bool) == hidden
        let delayMatches = hidden
            ? (preferences["autohide-delay"] as? NSNumber)?.doubleValue == 1000
            : preferences["autohide-delay"] == nil
        if autohideMatches && delayMatches {
            appliedHidden = hidden
            return
        }

        if snapshotDefaults.dictionary(forKey: snapshotKey) == nil {
            snapshotDefaults.set([
                "hadAutohide": preferences["autohide"] != nil,
                "autohide": preferences["autohide"] ?? false,
                "hadDelay": preferences["autohide-delay"] != nil,
                "delay": preferences["autohide-delay"] ?? 0.0
            ], forKey: snapshotKey)
        }
        if hidden {
            dockDefaults.set(true, forKey: "autohide")
            dockDefaults.set(1000.0, forKey: "autohide-delay")
        } else {
            dockDefaults.set(false, forKey: "autohide")
            dockDefaults.removeObject(forKey: "autohide-delay")
        }
        dockDefaults.synchronize()
        appliedHidden = hidden
        restartDockAction()
    }

    func restore() {
        guard let snapshot = snapshotDefaults.dictionary(forKey: snapshotKey),
              let dockDefaults else {
            appliedHidden = nil
            return
        }
        let preferences = dockDefaults.persistentDomain(forName: domain) ?? [:]
        let hadAutohide = snapshot["hadAutohide"] as? Bool == true
        let hadDelay = snapshot["hadDelay"] as? Bool == true
        let originalAutohide = snapshot["autohide"] as? Bool ?? false
        let originalDelay = (snapshot["delay"] as? NSNumber)?.doubleValue ?? 0
        let needsRestore = (hadAutohide
            ? (preferences["autohide"] as? Bool) != originalAutohide
            : preferences["autohide"] != nil) ||
            (hadDelay
                ? (preferences["autohide-delay"] as? NSNumber)?.doubleValue != originalDelay
                : preferences["autohide-delay"] != nil)
        guard needsRestore else {
            snapshotDefaults.removeObject(forKey: snapshotKey)
            appliedHidden = nil
            return
        }
        if hadAutohide {
            dockDefaults.set(originalAutohide, forKey: "autohide")
        } else {
            dockDefaults.removeObject(forKey: "autohide")
        }
        if hadDelay {
            dockDefaults.set(originalDelay, forKey: "autohide-delay")
        } else {
            dockDefaults.removeObject(forKey: "autohide-delay")
        }
        dockDefaults.synchronize()
        snapshotDefaults.removeObject(forKey: snapshotKey)
        appliedHidden = nil
        restartDockAction()
    }

    private static func restartSystemDock() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Dock"]
        try? process.run()
    }
}
