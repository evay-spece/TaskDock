import Foundation

@main
struct ModePreferenceSelftest {
    static func main() {
        let suite = "TaskDockPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(0.35, forKey: "taskdock.nonSelectedItemTransparency")
        defaults.set(true, forKey: "taskdock.showHiddenApps")
        defaults.set(true, forKey: "taskdock.finderTabsAsWindows")
        let initialTaskbar = ModePreferenceStorage.load(mode: "taskbar", defaults: defaults)
        precondition(initialTaskbar.transparency == 0.35)
        precondition(initialTaskbar.showHiddenApps && initialTaskbar.finderTabsAsWindows)

        let custom = ModePreferenceSnapshot(
            transparency: 0.5,
            showHiddenApps: false, finderTabsAsWindows: false
        )
        ModePreferenceStorage.save(custom, mode: "taskbar", defaults: defaults)
        precondition(ModePreferenceStorage.load(mode: "taskbar", defaults: defaults) == custom)

        defaults.set(9.0, forKey: "taskdock.mode.dockCompanion.nonSelectedItemTransparency")
        let invalid = ModePreferenceStorage.load(mode: "dockCompanion", defaults: defaults)
        precondition(invalid.transparency == 0.7)
        defaults.set(Double.nan, forKey: "taskdock.mode.dockCompanion.nonSelectedItemTransparency")
        precondition(ModePreferenceStorage.load(mode: "dockCompanion", defaults: defaults).transparency == 0)
        print("MODE_PREFERENCES_OK")
    }
}
