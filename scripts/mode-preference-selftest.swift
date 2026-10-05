import Foundation

@main
struct ModePreferenceSelftest {
    static func main() {
        let suite = "TaskDockPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set("light", forKey: "taskdock.appearance")
        defaults.set(0.35, forKey: "taskdock.nonSelectedItemTransparency")
        defaults.set(true, forKey: "taskdock.showHiddenApps")
        defaults.set(true, forKey: "taskdock.finderTabsAsWindows")
        for mode in ["taskbar", "matrix"] {
            let preferences = ModePreferenceStorage.load(mode: mode, defaults: defaults)
            precondition(preferences.appearance == "light")
            precondition(preferences.transparency == 0.35)
            precondition(preferences.showHiddenApps && preferences.finderTabsAsWindows)
        }
        precondition(ModePreferenceStorage.load(mode: "dockCompanion", defaults: defaults).appearance == "system")

        let custom = ModePreferenceSnapshot(
            appearance: "dark", transparency: 0.5,
            showHiddenApps: false, finderTabsAsWindows: false
        )
        ModePreferenceStorage.save(custom, mode: "taskbar", defaults: defaults)
        precondition(ModePreferenceStorage.load(mode: "taskbar", defaults: defaults) == custom)
        precondition(ModePreferenceStorage.load(mode: "matrix", defaults: defaults).appearance == "light")
        precondition(defaults.string(forKey: "taskdock.appearance") == "light")

        defaults.set("invalid", forKey: "taskdock.mode.matrix.appearance")
        defaults.set(9.0, forKey: "taskdock.mode.matrix.nonSelectedItemTransparency")
        let invalid = ModePreferenceStorage.load(mode: "matrix", defaults: defaults)
        precondition(invalid.appearance == "light" && invalid.transparency == 0.7)
        defaults.set(Double.nan, forKey: "taskdock.mode.matrix.nonSelectedItemTransparency")
        precondition(ModePreferenceStorage.load(mode: "matrix", defaults: defaults).transparency == 0)
        print("MODE_PREFERENCES_OK")
    }
}
