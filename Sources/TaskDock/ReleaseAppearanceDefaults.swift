import Foundation

/// Applies the release owner's portable appearance once per app version.
/// Favorites, folders, app history, licenses and feature permissions stay local.
enum ReleaseAppearanceDefaults {
    private static let appliedVersionKey = "taskdock.appliedAppearanceDefaultsVersion"

    static func applyIfNeeded(
        version: String,
        to defaults: UserDefaults = .standard
    ) {
        guard version == ReleaseAppearanceSnapshot.version,
              defaults.string(forKey: appliedVersionKey) != version else { return }
        for (key, value) in ReleaseAppearanceSnapshot.values {
            defaults.set(value, forKey: key)
        }
        defaults.set(version, forKey: appliedVersionKey)
    }
}
