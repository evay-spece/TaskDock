import Foundation

@main struct SettingsEntryResetSelfTest {
    static func main() {
        let name = "TaskDockEntryResetTest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let finder = UserDefaults(suiteName: name + ".finder")!
        defer {
            defaults.removePersistentDomain(forName: name)
            finder.removePersistentDomain(forName: name + ".finder")
        }
        defaults.set(62.0, forKey: "taskdock.taskbarHeight")
        defaults.set("my-favorites", forKey: "taskdock.favoriteApps")
        finder.set(true, forKey: "rightClickFeatureEnabledV1")
        for build in ["185", "186"] {
            defaults.set(true, forKey: "fusionSettingsVisibleV1")
            defaults.set(true, forKey: "developerDebugSettingsVisibleV1")
            finder.set(true, forKey: "rightClickSettingsVisibleV1")
            EasterEggSettingsEntryReset.applyIfNeeded(build: build, to: defaults, finderDefaults: finder)
            precondition(!defaults.bool(forKey: "fusionSettingsVisibleV1"))
            precondition(!defaults.bool(forKey: "developerDebugSettingsVisibleV1"))
            precondition(!finder.bool(forKey: "rightClickSettingsVisibleV1"))
            precondition(finder.bool(forKey: "rightClickFeatureEnabledV1"))
            precondition(defaults.double(forKey: "taskdock.taskbarHeight") == 62)
            precondition(defaults.string(forKey: "taskdock.favoriteApps") == "my-favorites")
            defaults.set(true, forKey: "developerDebugSettingsVisibleV1")
            EasterEggSettingsEntryReset.applyIfNeeded(build: build, to: defaults, finderDefaults: finder)
            precondition(defaults.bool(forKey: "developerDebugSettingsVisibleV1"))
        }
        print("SETTINGS_ENTRY_RESET_OK new-build-only feature-and-user-values-preserved")
    }
}
