import Foundation

/// One-time 1.7.0 taskbar layout migration captured from the release owner's Mac.
/// Personal favorites, folders, downloads, window history and license state remain local.
enum ReleaseDefaults170 {
    private static let migrationKey = "taskdock.appliedTaskbarDefaultsVersion"
    private static let version = "1.7.0"

    static func applyIfNeeded(to defaults: UserDefaults = .standard) {
        guard defaults.string(forKey: migrationKey) != version else { return }
        let values: [String: Any] = [
            "taskdock.layoutMode": "taskbar",
            "taskdock.appearanceModeV1": "dark",
            "taskdock.taskbarHeight": 50.0,
            "taskdock.taskbarLeadingInset": 88.0,
            "taskdock.taskbarBackgroundTransparency": 0.0,
            "taskdock.taskbarItemFontSize": 8.0,
            "taskdock.taskbarItemWidthMode": "adaptive",
            "taskdock.taskbarCollapseSameAppWindows": false,
            "taskdock.taskItemHighlightStyle": "white",
            "taskdock.favoriteMagnificationEnabled": true,
            "taskdock.favoriteMagnificationScale": 1.8,
            "taskdock.dockFavoritesSyncEnabled": false,
            "taskdock.mode.taskbar.nonSelectedItemTransparency": 0.5,
            "taskdock.mode.taskbar.showHiddenApps": true,
            "taskdock.mode.taskbar.finderTabsAsWindows": true,
            "taskdock.experimentalActiveGlassV1": true,
            "taskdock.customGlassClarityV1": 0.0
        ]
        for (key, value) in values { defaults.set(value, forKey: key) }
        defaults.set(version, forKey: migrationKey)
    }
}

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
