import Foundation

@main
struct ReleaseAppearanceSelfTest {
    static func main() {
        let name = "taskdock.release-appearance-selftest.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else { fatalError("No test defaults") }
        defer { defaults.removePersistentDomain(forName: name) }

        defaults.set(0.33, forKey: "taskbarItemHazeStrengthV1")
        defaults.set("personal-favorite", forKey: "taskdock.favoriteApps")
        defaults.set("personal-license", forKey: "taskdock.license")
        ReleaseAppearanceDefaults.applyIfNeeded(version: "0.0.0", to: defaults)
        precondition(defaults.double(forKey: "taskbarItemHazeStrengthV1") == 0.33)

        ReleaseAppearanceDefaults.applyIfNeeded(version: ReleaseAppearanceSnapshot.version, to: defaults)
        precondition(defaults.double(forKey: "taskbarItemHazeStrengthV1") ==
                     ReleaseAppearanceSnapshot.values["taskbarItemHazeStrengthV1"] as? Double)
        precondition(defaults.string(forKey: "taskdock.favoriteApps") == "personal-favorite")
        precondition(defaults.string(forKey: "taskdock.license") == "personal-license")

        defaults.set(0.42, forKey: "taskbarItemHazeStrengthV1")
        ReleaseAppearanceDefaults.applyIfNeeded(version: ReleaseAppearanceSnapshot.version, to: defaults)
        precondition(defaults.double(forKey: "taskbarItemHazeStrengthV1") == 0.42)
        print("RELEASE_APPEARANCE_OK first-launch-overwrite personal-data-preserved same-version-preserved")
    }
}
