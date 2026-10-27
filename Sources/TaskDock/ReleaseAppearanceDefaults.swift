import Foundation

/// Applies the release owner's portable appearance once per app version.
/// Favorites, folders, app history, licenses and feature permissions stay local.
enum ReleaseAppearanceDefaults {
    private static let appliedVersionKey = "taskdock.appliedAppearanceDefaultsVersion"

    static func applyIfNeeded(
        version: String,
        to defaults: UserDefaults = .standard,
        finderDefaults: UserDefaults? = UserDefaults(suiteName: "com.taskdock.finder.settings")
    ) {
        guard version == ReleaseAppearanceSnapshot.version,
              defaults.string(forKey: appliedVersionKey) != version else { return }
        for (key, value) in ReleaseAppearanceSnapshot.values {
            defaults.set(value, forKey: key)
        }
        defaults.set("adaptive", forKey: "taskdock.taskbarItemWidthMode")
        defaults.set(false, forKey: "taskdock.taskbarCollapseSameAppWindows")
        if version == "1.9.0" {
            finderDefaults?.set(false, forKey: "rightClickFeatureEnabledV1")
        }
        defaults.set(version, forKey: appliedVersionKey)
    }
}
