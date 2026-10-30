import Foundation

@main
struct ReleaseAppearanceSelfTest {
    static func main() {
        let name = "taskdock.release-appearance-selftest.\(UUID().uuidString)"
        let finderName = name + ".finder"
        let defaults = UserDefaults(suiteName: name)!
        let finder = UserDefaults(suiteName: finderName)!
        defer {
            defaults.removePersistentDomain(forName: name)
            finder.removePersistentDomain(forName: finderName)
        }
        // Simulate an older installation with no migration marker at all.
        defaults.set(0.33, forKey: "taskbarItemHazeStrengthV1")
        defaults.set(62.0, forKey: "taskdock.taskbarHeight")
        defaults.set("fixed", forKey: "taskdock.taskbarItemWidthMode")
        defaults.set(true, forKey: "taskdock.taskbarCollapseSameAppWindows")
        defaults.set("personal-favorite", forKey: "taskdock.favoriteApps")
        defaults.set("personal-license", forKey: "taskdock.license")
        finder.set(true, forKey: "rightClickFeatureEnabledV1")
        let saved = defaults.persistentDomain(forName: name)! as NSDictionary
        for version in ["1.11.0", "1.12.0"] {
            ReleaseAppearanceDefaults.applyIfNeeded(version: version, to: defaults, finderDefaults: finder)
            precondition(saved.isEqual(to: defaults.persistentDomain(forName: name)!), "Update mutated persisted settings")
            precondition(defaults.double(forKey: "taskbarItemHazeStrengthV1") == 0.33)
            precondition(defaults.string(forKey: "taskdock.taskbarItemWidthMode") == "fixed")
            precondition(defaults.bool(forKey: "taskdock.taskbarCollapseSameAppWindows"))
            precondition(finder.bool(forKey: "rightClickFeatureEnabledV1"))
        }
        let fallbackKey = "smallBubbleFontSizeV1"
        precondition(defaults.object(forKey: fallbackKey) != nil, "Missing setting has no fallback")
        precondition(defaults.persistentDomain(forName: name)?[fallbackKey] == nil, "Fallback was forced into storage")
        defaults.set(0.42, forKey: "taskbarItemHazeStrengthV1")
        ReleaseAppearanceDefaults.applyIfNeeded(version: "1.11.0", to: defaults, finderDefaults: finder)
        precondition(defaults.double(forKey: "taskbarItemHazeStrengthV1") == 0.42)
        print("RELEASE_APPEARANCE_OK upgrade-preserved old-install-preserved fallback-only personal-data-preserved")
    }
}
