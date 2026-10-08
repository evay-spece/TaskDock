import Foundation

public struct ModePreferenceSnapshot: Equatable {
    public let transparency: Double
    public let showHiddenApps: Bool
    public let finderTabsAsWindows: Bool

    public init(transparency: Double, showHiddenApps: Bool, finderTabsAsWindows: Bool) {
        self.transparency = transparency
        self.showHiddenApps = showHiddenApps
        self.finderTabsAsWindows = finderTabsAsWindows
    }
}

public enum ModePreferenceStorage {
    public static func load(mode: String, defaults: UserDefaults) -> ModePreferenceSnapshot {
        let legacyTransparency = defaults.object(forKey: "taskdock.nonSelectedItemTransparency") as? Double ?? 0
        let transparency = defaults.object(forKey: key(mode, "nonSelectedItemTransparency")) as? Double
            ?? legacyTransparency
        return ModePreferenceSnapshot(
            transparency: normalizedTransparency(transparency),
            showHiddenApps: defaults.object(forKey: key(mode, "showHiddenApps")) as? Bool
                ?? defaults.bool(forKey: "taskdock.showHiddenApps"),
            finderTabsAsWindows: defaults.object(forKey: key(mode, "finderTabsAsWindows")) as? Bool
                ?? defaults.bool(forKey: "taskdock.finderTabsAsWindows")
        )
    }

    public static func save(_ snapshot: ModePreferenceSnapshot, mode: String, defaults: UserDefaults) {
        defaults.set(normalizedTransparency(snapshot.transparency), forKey: key(mode, "nonSelectedItemTransparency"))
        defaults.set(snapshot.showHiddenApps, forKey: key(mode, "showHiddenApps"))
        defaults.set(snapshot.finderTabsAsWindows, forKey: key(mode, "finderTabsAsWindows"))
    }

    private static func key(_ mode: String, _ field: String) -> String {
        "taskdock.mode.\(mode).\(field)"
    }

    private static func normalizedTransparency(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 0.7) : 0
    }
}
