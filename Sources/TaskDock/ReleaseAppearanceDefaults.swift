import Foundation

/// Supplies fallback values for new/missing settings. Updates preserve every
/// persisted user preference; owner snapshots are never forced onto installations.
enum ReleaseAppearanceDefaults {
    static func applyIfNeeded(
        version: String,
        to defaults: UserDefaults = .standard,
        finderDefaults: UserDefaults? = UserDefaults(suiteName: "com.taskdock.finder.settings")
    ) {
        guard !version.isEmpty else { return }
        defaults.register(defaults: ReleaseAppearanceSnapshot.values)
    }
}
