import Foundation

@main
struct Release170DefaultsSelfTest {
    static func main() {
        let mainSuite = "taskdock.release170.test.\(UUID().uuidString)"
        let finderSuite = "taskdock.release170.finder.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: mainSuite)!
        let finder = UserDefaults(suiteName: finderSuite)!
        defer {
            defaults.removePersistentDomain(forName: mainSuite)
            finder.removePersistentDomain(forName: finderSuite)
        }
        defaults.set(Data("favorites".utf8), forKey: "taskdock.favoriteApps")
        defaults.set(Data("folders".utf8), forKey: "taskdock.favoriteFolders")
        defaults.set("license", forKey: "taskdock.license")
        defaults.set(35.0, forKey: "taskdock.taskbarHeight")
        defaults.set(true, forKey: "fusionSettingsVisibleV1")
        defaults.set(true, forKey: "developerDebugSettingsVisibleV1")
        finder.set(true, forKey: "rightClickSettingsVisibleV1")
        finder.set(true, forKey: "rightClickFeatureEnabledV1")
        ReleaseDefaults170.applyIfNeeded(to: defaults)
        EasterEggSettingsEntryReset.applyIfNeeded(build: "116", to: defaults, finderDefaults: finder)
        precondition(defaults.double(forKey: "taskdock.taskbarHeight") == 50)
        precondition(defaults.double(forKey: "taskdock.taskbarLeadingInset") == 88)
        precondition(defaults.double(forKey: "taskdock.taskbarItemFontSize") == 8)
        precondition(defaults.double(forKey: "taskdock.mode.taskbar.nonSelectedItemTransparency") == 0.5)
        precondition(defaults.string(forKey: "taskdock.taskbarItemWidthMode") == "adaptive")
        precondition(defaults.data(forKey: "taskdock.favoriteApps") == Data("favorites".utf8))
        precondition(defaults.data(forKey: "taskdock.favoriteFolders") == Data("folders".utf8))
        precondition(defaults.string(forKey: "taskdock.license") == "license")
        precondition(!defaults.bool(forKey: "fusionSettingsVisibleV1"))
        precondition(!defaults.bool(forKey: "developerDebugSettingsVisibleV1"))
        precondition(!finder.bool(forKey: "rightClickSettingsVisibleV1"))
        precondition(finder.bool(forKey: "rightClickFeatureEnabledV1"))
        defaults.set(60.0, forKey: "taskdock.taskbarHeight")
        defaults.set(true, forKey: "fusionSettingsVisibleV1")
        ReleaseDefaults170.applyIfNeeded(to: defaults)
        EasterEggSettingsEntryReset.applyIfNeeded(build: "116", to: defaults, finderDefaults: finder)
        precondition(defaults.double(forKey: "taskdock.taskbarHeight") == 60)
        precondition(defaults.bool(forKey: "fusionSettingsVisibleV1"))
        EasterEggSettingsEntryReset.applyIfNeeded(build: "117", to: defaults, finderDefaults: finder)
        precondition(!defaults.bool(forKey: "fusionSettingsVisibleV1"))
        precondition(defaults.double(forKey: "taskdock.taskbarHeight") == 60)
        print("RELEASE_170_DEFAULTS_OK")
    }
}
