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
    private let reservationSnapshotKey = "taskdock.originalDockReservationPreferencesV1"
    private let reservationKeys = ["orientation", "tilesize", "magnification", "launchanim", "no-bouncing"]
    private var reservationHeight: CGFloat?
    private var reservationTileSize: CGFloat = 0
    private var calibrationCount = 0
    private var settleUntil = Date.distantPast

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

    func synchronize(hidden: Bool, accessAllowed: Bool = true) {
        guard accessAllowed else {
            restore()
            return
        }
        guard let dockDefaults else { return }
        let reservationChanged = restoreReservationOverrides()
        guard appliedHidden != hidden || reservationChanged else { return }
        let preferences = dockDefaults.persistentDomain(forName: domain) ?? [:]
        let autohideMatches = (preferences["autohide"] as? Bool) == hidden
        let delayMatches = hidden
            ? (preferences["autohide-delay"] as? NSNumber)?.doubleValue == 1000
            : preferences["autohide-delay"] == nil
        if autohideMatches && delayMatches {
            appliedHidden = hidden
            if reservationChanged { restartDockAction() }
            return
        }

        captureVisibilityPreferences(preferences)
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

    /// Keeps the real Dock visible beneath TaskDock, so the WindowServer owns the inset.
    func synchronizeReservation(height: CGFloat, measuredInset: CGFloat? = nil,
                                accessAllowed: Bool = true, now: Date = Date()) {
        guard accessAllowed, height.isFinite, height > 0 else { restore(); return }
        guard let dockDefaults else { return }
        let target = min(max(height, 32), 160)
        if let existing = reservationHeight, abs(existing - target) < 0.5 {
            // Allow the restarted Dock to settle; never repeatedly restart on a mismatch.
            guard now >= settleUntil, calibrationCount < 2,
                  let measuredInset, measuredInset.isFinite, measuredInset > 0,
                  abs(measuredInset - target) > 2 else { return }
            let tile = min(max(reservationTileSize + target - measuredInset, 16), 128)
            guard abs(tile - reservationTileSize) >= 1 else { return }
            reservationTileSize = tile
            dockDefaults.set(tile, forKey: "tilesize")
            dockDefaults.synchronize()
            calibrationCount += 1
            settleUntil = now.addingTimeInterval(2)
            restartDockAction()
            return
        }
        let preferences = dockDefaults.persistentDomain(forName: domain) ?? [:]
        captureVisibilityPreferences(preferences)
        if snapshotDefaults.dictionary(forKey: reservationSnapshotKey) == nil {
            var saved: [String: Any] = [:]
            for key in reservationKeys {
                saved[key] = ["present": preferences[key] != nil, "value": preferences[key] ?? 0]
            }
            snapshotDefaults.set(saved, forKey: reservationSnapshotKey)
        }
        reservationHeight = target
        reservationTileSize = min(max(target - 16, 16), 128)
        calibrationCount = 0
        settleUntil = now.addingTimeInterval(2)
        appliedHidden = nil
        dockDefaults.set(false, forKey: "autohide")
        dockDefaults.removeObject(forKey: "autohide-delay")
        dockDefaults.set("bottom", forKey: "orientation")
        dockDefaults.set(reservationTileSize, forKey: "tilesize")
        dockDefaults.set(false, forKey: "magnification")
        dockDefaults.set(false, forKey: "launchanim")
        dockDefaults.set(true, forKey: "no-bouncing")
        dockDefaults.synchronize()
        restartDockAction()
    }

    private func captureVisibilityPreferences(_ preferences: [String: Any]) {
        guard snapshotDefaults.dictionary(forKey: snapshotKey) == nil else { return }
        snapshotDefaults.set([
            "hadAutohide": preferences["autohide"] != nil,
            "autohide": preferences["autohide"] ?? false,
            "hadDelay": preferences["autohide-delay"] != nil,
            "delay": preferences["autohide-delay"] ?? 0.0
        ], forKey: snapshotKey)
    }

    @discardableResult
    private func restoreReservationOverrides() -> Bool {
        reservationHeight = nil
        guard let saved = snapshotDefaults.dictionary(forKey: reservationSnapshotKey),
              let dockDefaults else { return false }
        var changed = false
        for key in reservationKeys {
            guard let value = saved[key] as? [String: Any] else { continue }
            let before = dockDefaults.object(forKey: key) as? NSObject
            if value["present"] as? Bool == true {
                dockDefaults.set(value["value"], forKey: key)
            } else { dockDefaults.removeObject(forKey: key) }
            let after = dockDefaults.object(forKey: key) as? NSObject
            if before != after { changed = true }
        }
        dockDefaults.synchronize()
        snapshotDefaults.removeObject(forKey: reservationSnapshotKey)
        return changed
    }

    func restore() {
        let reservationChanged = restoreReservationOverrides()
        guard let snapshot = snapshotDefaults.dictionary(forKey: snapshotKey),
              let dockDefaults else {
            appliedHidden = nil
            if reservationChanged { restartDockAction() }
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
            if reservationChanged { restartDockAction() }
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
