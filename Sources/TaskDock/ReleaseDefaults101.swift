import Foundation

enum ReleaseDefaults101 {
    private static let migrationKey = "taskdock.appliedDefaultsVersion"
    private static let version = "1.0.1"

    static func applyIfNeeded(to defaults: UserDefaults = .standard) {
        guard defaults.string(forKey: migrationKey) != version else { return }

        // Public, portable UI preferences captured from the release owner's Mac.
        // Keep personal folders, window rules, recent apps and app history local.
        let values: [String: Any] = [
            "taskdock.layoutMode": "taskbar",
            "taskdock.taskbarWidthMode": "fullWidth",
            "taskdock.taskbarHeight": 48.0,
            "taskdock.taskbarLeadingInset": 72.0,
            "taskdock.taskbarItemFontSize": 10.0,
            "taskdock.taskbarFavoriteFlowWidth": 516.0,
            "taskdock.favoriteMagnificationEnabled": true,
            "taskdock.taskbarCollapseSameAppWindows": false,
            "taskdock.taskbarReduceMotion": false,
            "taskdock.showApplicationName": false,
            "taskdock.taskItemHighlightStyle": "systemAccent",
            "taskdock.toggleModifier": "option",
            "taskdock.dockCompanionLeftAppKeys": ["com.apple.finder"],
            "taskdock.dockCompanionRightAppKeys": ["com.microsoft.Excel"],
            "taskdock.dockCompanionRightAppsCustomized": true,
            "taskdock.dockCompanionMinimumWindowCount": 1,
            "taskdock.dockCompanionCollapseThreshold": 3,
            "taskdock.dockCompanionShowsRecentWindows": true,
            "taskdock.dockCompanionShowsBottomBar": false,
            "taskdock.dockCompanionOverlayEnabled": false,
            "taskdock.mode.taskbar.appearance": "dark",
            "taskdock.mode.taskbar.nonSelectedItemTransparency": 0.3,
            "taskdock.mode.taskbar.showHiddenApps": true,
            "taskdock.mode.taskbar.finderTabsAsWindows": true,
            "taskdock.mode.dockCompanion.appearance": "system",
            "taskdock.mode.dockCompanion.nonSelectedItemTransparency": 0.35,
            "taskdock.mode.dockCompanion.showHiddenApps": true,
            "taskdock.mode.dockCompanion.finderTabsAsWindows": true,
            "taskdock.mode.matrix.appearance": "dark",
            "taskdock.mode.matrix.nonSelectedItemTransparency": 0.35,
            "taskdock.mode.matrix.showHiddenApps": true,
            "taskdock.mode.matrix.finderTabsAsWindows": true
        ]
        for (key, value) in values { defaults.set(value, forKey: key) }

        let favorites: [FavoriteApp] = [
            ("com.apple.finder", "访达"),
            ("com.apple.Safari", "Safari"),
            ("com.apple.iCal", "日历"),
            ("com.apple.reminders", "提醒事项"),
            ("com.apple.Notes", "备忘录")
        ].map { identifier, name in
            FavoriteApp(id: identifier, bundleIdentifier: identifier,
                        applicationName: name, bundlePath: nil)
        }
        guard let data = try? JSONEncoder().encode(favorites) else { return }
        defaults.set(data, forKey: "taskdock.favoriteApps")
        defaults.set(version, forKey: migrationKey)
    }
}
