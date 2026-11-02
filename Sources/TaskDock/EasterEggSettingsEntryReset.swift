import Foundation

/// Hide all three secret Settings tabs once for each installed build.
/// Their feature toggles and user data are deliberately left intact.
enum EasterEggSettingsEntryReset {
    private static let appliedBuildKey = "taskdock.hiddenSettingsEntriesForBuild"

    static func applyIfNeeded(
        build: String,
        to defaults: UserDefaults = .standard,
        finderDefaults: UserDefaults? = UserDefaults(suiteName: "com.taskdock.finder.settings")
    ) {
        guard !build.isEmpty, defaults.string(forKey: appliedBuildKey) != build else { return }
        defaults.set(false, forKey: "fusionSettingsVisibleV1")
        defaults.set(false, forKey: "developerDebugSettingsVisibleV1")
        finderDefaults?.set(false, forKey: "rightClickSettingsVisibleV1")
        defaults.set(build, forKey: appliedBuildKey)
    }
}
