import AppKit
import SwiftUI

enum TaskbarAppearance: String, CaseIterable, Identifiable {
    case light
    case dark

    var id: String { rawValue }
    var label: String { self == .light ? "浅色" : "深色" }
    var colorScheme: ColorScheme { self == .light ? .light : .dark }
}

enum TaskItemHighlightStyle: String, CaseIterable, Identifiable {
    case systemAccent
    case white

    var id: String { rawValue }
    var label: String { self == .systemAccent ? "系统强调色" : "白色" }
}

enum TaskDockLayoutMode: String, CaseIterable, Identifiable {
    case taskbar
    case matrix
    case dockCompanion

    var id: String { rawValue }
    var label: String {
        switch self {
        case .taskbar: return "任务栏"
        case .matrix: return "窗口矩阵"
        case .dockCompanion: return "Dock 融合"
        }
    }
    var systemImage: String {
        switch self {
        case .taskbar: return "rectangle.bottomthird.inset.filled"
        case .matrix: return "rectangle.grid.2x2.fill"
        case .dockCompanion: return "dock.rectangle"
        }
    }
}

enum TaskbarAlignment: String, CaseIterable, Identifiable {
    case left
    case center
    case right

    var id: String { rawValue }
    var label: String {
        switch self {
        case .left: return "左侧"
        case .center: return "居中"
        case .right: return "右侧"
        }
    }
}

enum TaskbarWidthMode: String, CaseIterable, Identifiable {
    case adaptive
    case fullWidth

    var id: String { rawValue }
    var label: String {
        switch self {
        case .adaptive: return "适应长度"
        case .fullWidth: return "左右铺满"
        }
    }
}

enum DockCompanionAppSide: Equatable {
    case left
    case right
    case hidden
}

enum TaskbarToggleModifier: String, CaseIterable, Identifiable {
    case option
    case command
    case control

    var id: String { rawValue }
    var label: String {
        switch self {
        case .option: return "⌥ Option"
        case .command: return "⌘ Command"
        case .control: return "⌃ Control"
        }
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var blacklistedAppKeys: Set<String> { didSet { save() } }
    @Published private(set) var blockedWindowRules: [BlockedWindowRule] { didSet { save() } }
    @Published var showHiddenApps: Bool { didSet { save() } }
    @Published var showApplicationName: Bool { didSet { save() } }
    @Published var nonSelectedItemTransparency: Double { didSet { save() } }
    @Published var taskItemHighlightStyle: TaskItemHighlightStyle { didSet { save() } }
    @Published var appearance: TaskbarAppearance { didSet { save() } }
    @Published var layoutMode: TaskDockLayoutMode { didSet { save() } }
    @Published var dockCompanionHeight: CGFloat = 39
    @Published var taskbarAlignment: TaskbarAlignment { didSet { save() } }
    @Published var taskbarWidthMode: TaskbarWidthMode { didSet { save() } }
    @Published var favoriteMagnificationEnabled: Bool { didSet { save() } }
    @Published var hideSystemDock: Bool { didSet { save() } }
    @Published private(set) var dockCompanionLeftAppKeys: Set<String> { didSet { save() } }
    @Published private(set) var dockCompanionRightAppKeys: Set<String> { didSet { save() } }
    @Published private(set) var dockCompanionRightAppsCustomized: Bool { didSet { save() } }
    @Published var dockCompanionMinimumWindowCount: Int { didSet { save() } }
    @Published var dockCompanionShowsBottomBar: Bool { didSet { save() } }
    @Published var dockCompanionOverlayEnabled: Bool { didSet { save() } }
    @Published var toggleModifier: TaskbarToggleModifier { didSet { save() } }
    @Published private(set) var appOrder: [String] { didSet { save() } }
    @Published private(set) var favoriteApps: [FavoriteApp] { didSet { save() } }

    private let defaults = UserDefaults.standard
    private let blacklistKey = "taskdock.blacklistedAppKeys"
    private let blockedWindowRulesKey = "taskdock.blockedWindowRules"
    private let hiddenAppsKey = "taskdock.showHiddenApps"
    private let showApplicationNameKey = "taskdock.showApplicationName"
    private let nonSelectedItemTransparencyKey = "taskdock.nonSelectedItemTransparency"
    private let taskItemHighlightStyleKey = "taskdock.taskItemHighlightStyle"
    private let appearanceKey = "taskdock.appearance"
    private let layoutModeKey = "taskdock.layoutMode"
    private let taskbarAlignmentKey = "taskdock.taskbarAlignment"
    private let taskbarWidthModeKey = "taskdock.taskbarWidthMode"
    private let favoriteMagnificationEnabledKey = "taskdock.favoriteMagnificationEnabled"
    private let hideSystemDockKey = "taskdock.hideSystemDock"
    private let dockCompanionLeftAppKeysKey = "taskdock.dockCompanionLeftAppKeys"
    private let dockCompanionRightAppKeysKey = "taskdock.dockCompanionRightAppKeys"
    private let dockCompanionRightAppsCustomizedKey = "taskdock.dockCompanionRightAppsCustomized"
    private let dockCompanionMinimumWindowCountKey = "taskdock.dockCompanionMinimumWindowCount"
    private let dockCompanionShowsBottomBarKey = "taskdock.dockCompanionShowsBottomBar"
    private let dockCompanionOverlayEnabledKey = "taskdock.dockCompanionOverlayEnabled"
    private let toggleModifierKey = "taskdock.toggleModifier"
    private let appOrderKey = "taskdock.appOrder"
    private let favoriteAppsKey = "taskdock.favoriteApps"

    init() {
        blacklistedAppKeys = Set(defaults.stringArray(forKey: blacklistKey) ?? [])
        if let data = defaults.data(forKey: blockedWindowRulesKey),
           let decoded = try? JSONDecoder().decode([BlockedWindowRule].self, from: data) {
            var seenRuleIDs = Set<String>()
            blockedWindowRules = decoded.filter { seenRuleIDs.insert($0.id).inserted }
        } else {
            blockedWindowRules = []
        }
        showHiddenApps = defaults.bool(forKey: hiddenAppsKey)
        showApplicationName = defaults.object(forKey: showApplicationNameKey) as? Bool ?? true
        nonSelectedItemTransparency = min(max(defaults.object(forKey: nonSelectedItemTransparencyKey) as? Double ?? 0, 0), 0.7)
        taskItemHighlightStyle = TaskItemHighlightStyle(
            rawValue: defaults.string(forKey: taskItemHighlightStyleKey) ?? "white"
        ) ?? .white
        appearance = TaskbarAppearance(rawValue: defaults.string(forKey: appearanceKey) ?? "dark") ?? .dark
        layoutMode = TaskDockLayoutMode(rawValue: defaults.string(forKey: layoutModeKey) ?? "matrix") ?? .matrix
        taskbarAlignment = TaskbarAlignment(rawValue: defaults.string(forKey: taskbarAlignmentKey) ?? "center") ?? .center
        taskbarWidthMode = TaskbarWidthMode(rawValue: defaults.string(forKey: taskbarWidthModeKey) ?? "adaptive") ?? .adaptive
        favoriteMagnificationEnabled = defaults.object(forKey: favoriteMagnificationEnabledKey) as? Bool ?? true
        hideSystemDock = defaults.bool(forKey: hideSystemDockKey)
        dockCompanionLeftAppKeys = Set(defaults.stringArray(forKey: dockCompanionLeftAppKeysKey) ?? ["com.apple.finder"])
        dockCompanionRightAppKeys = Set(defaults.stringArray(forKey: dockCompanionRightAppKeysKey) ?? [])
        dockCompanionRightAppsCustomized = defaults.bool(forKey: dockCompanionRightAppsCustomizedKey)
        let savedMinimumWindowCount = defaults.object(forKey: dockCompanionMinimumWindowCountKey) as? Int ?? 2
        dockCompanionMinimumWindowCount = min(max(savedMinimumWindowCount, 1), 20)
        dockCompanionShowsBottomBar = defaults.object(forKey: dockCompanionShowsBottomBarKey) as? Bool ?? true
        dockCompanionOverlayEnabled = defaults.object(forKey: dockCompanionOverlayEnabledKey) as? Bool ?? false
        toggleModifier = TaskbarToggleModifier(rawValue: defaults.string(forKey: toggleModifierKey) ?? "option") ?? .option
        var seenAppKeys = Set<String>()
        appOrder = (defaults.stringArray(forKey: appOrderKey) ?? []).filter {
            seenAppKeys.insert($0).inserted
        }
        if let data = defaults.data(forKey: favoriteAppsKey),
           let decoded = try? JSONDecoder().decode([FavoriteApp].self, from: data) {
            var seenFavoriteIDs = Set<String>()
            favoriteApps = decoded.filter { seenFavoriteIDs.insert($0.id).inserted }
        } else {
            favoriteApps = []
        }
        defaults.set(appOrder, forKey: appOrderKey)
    }

    func toggleBlacklist(for appKey: String) {
        if blacklistedAppKeys.contains(appKey) {
            blacklistedAppKeys.remove(appKey)
        } else {
            blacklistedAppKeys.insert(appKey)
        }
    }

    func blockWindowType(for window: WindowModel) {
        let rule = BlockedWindowRule(window: window)
        guard !blockedWindowRules.contains(where: { $0.id == rule.id }) else { return }
        blockedWindowRules.append(rule)
    }

    func removeBlockedWindowRule(_ rule: BlockedWindowRule) {
        blockedWindowRules.removeAll { $0.id == rule.id }
    }

    func reconcileAppOrder(with appKeys: [String]) {
        var knownKeys = Set(appOrder)
        let newKeys = appKeys.filter { knownKeys.insert($0).inserted }
        guard !newKeys.isEmpty else { return }
        appOrder.append(contentsOf: newKeys)
    }

    func applyVisibleAppOrder(_ visibleKeys: [String]) {
        let visibleSet = Set(visibleKeys)
        var reordered = visibleKeys.makeIterator()
        let nextOrder = appOrder.map { key in
            visibleSet.contains(key) ? (reordered.next() ?? key) : key
        }
        guard nextOrder != appOrder else { return }
        appOrder = nextOrder
    }

    func isFavorite(_ appKey: String) -> Bool {
        favoriteApps.contains { $0.id == appKey }
    }

    func toggleFavorite(for window: WindowModel) {
        if let index = favoriteApps.firstIndex(where: { $0.id == window.appKey }) {
            favoriteApps.remove(at: index)
            return
        }

        let runningApp = NSRunningApplication(processIdentifier: window.pid)
        favoriteApps.append(FavoriteApp(
            id: window.appKey,
            bundleIdentifier: window.bundleIdentifier,
            applicationName: window.applicationName,
            bundlePath: runningApp?.bundleURL?.path
        ))
    }

    @discardableResult
    func addFavorite(applicationURL: URL) -> Bool {
        let url = applicationURL.standardizedFileURL
        guard url.pathExtension.lowercased() == "app",
              let bundle = Bundle(url: url),
              bundle.infoDictionary != nil else { return false }

        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let bundleIdentifier = bundle.bundleIdentifier
        let appKey = bundleIdentifier ?? "name:\(name)"
        guard !favoriteApps.contains(where: { $0.id == appKey }) else { return false }

        favoriteApps.append(FavoriteApp(
            id: appKey,
            bundleIdentifier: bundleIdentifier,
            applicationName: name,
            bundlePath: url.path
        ))
        return true
    }

    func removeFavorite(_ favorite: FavoriteApp) {
        favoriteApps.removeAll { $0.id == favorite.id }
    }

    func reorderFavorites(_ orderedIDs: [String]) {
        guard orderedIDs.count == favoriteApps.count,
              Set(orderedIDs) == Set(favoriteApps.map(\.id)) else { return }
        let favoritesByID = Dictionary(uniqueKeysWithValues: favoriteApps.map { ($0.id, $0) })
        let reordered = orderedIDs.compactMap { favoritesByID[$0] }
        guard reordered != favoriteApps else { return }
        favoriteApps = reordered
    }

    func dockCompanionSide(for appKey: String, availableAppKeys: Set<String>) -> DockCompanionAppSide {
        if dockCompanionLeftAppKeys.contains(appKey) { return .left }
        if dockCompanionRightAppsCustomized {
            return dockCompanionRightAppKeys.contains(appKey) ? .right : .hidden
        }
        return availableAppKeys.contains(appKey) ? .right : .hidden
    }

    func setDockCompanionLeft(_ isSelected: Bool, appKey: String) {
        if isSelected {
            dockCompanionLeftAppKeys.insert(appKey)
            dockCompanionRightAppKeys.remove(appKey)
        } else {
            dockCompanionLeftAppKeys.remove(appKey)
        }
    }

    func setDockCompanionRight(_ isSelected: Bool, appKey: String, availableAppKeys: Set<String>) {
        if !dockCompanionRightAppsCustomized {
            dockCompanionRightAppKeys = Set(availableAppKeys.filter { !dockCompanionLeftAppKeys.contains($0) })
            dockCompanionRightAppsCustomized = true
        }
        if isSelected {
            dockCompanionLeftAppKeys.remove(appKey)
            dockCompanionRightAppKeys.insert(appKey)
        } else {
            dockCompanionRightAppKeys.remove(appKey)
        }
    }

    private func save() {
        defaults.set(Array(blacklistedAppKeys), forKey: blacklistKey)
        if let data = try? JSONEncoder().encode(blockedWindowRules) {
            defaults.set(data, forKey: blockedWindowRulesKey)
        }
        defaults.set(showHiddenApps, forKey: hiddenAppsKey)
        defaults.set(showApplicationName, forKey: showApplicationNameKey)
        defaults.set(nonSelectedItemTransparency, forKey: nonSelectedItemTransparencyKey)
        defaults.set(taskItemHighlightStyle.rawValue, forKey: taskItemHighlightStyleKey)
        defaults.set(appearance.rawValue, forKey: appearanceKey)
        defaults.set(layoutMode.rawValue, forKey: layoutModeKey)
        defaults.set(taskbarAlignment.rawValue, forKey: taskbarAlignmentKey)
        defaults.set(taskbarWidthMode.rawValue, forKey: taskbarWidthModeKey)
        defaults.set(favoriteMagnificationEnabled, forKey: favoriteMagnificationEnabledKey)
        defaults.set(hideSystemDock, forKey: hideSystemDockKey)
        defaults.set(Array(dockCompanionLeftAppKeys), forKey: dockCompanionLeftAppKeysKey)
        defaults.set(Array(dockCompanionRightAppKeys), forKey: dockCompanionRightAppKeysKey)
        defaults.set(dockCompanionRightAppsCustomized, forKey: dockCompanionRightAppsCustomizedKey)
        defaults.set(dockCompanionMinimumWindowCount, forKey: dockCompanionMinimumWindowCountKey)
        defaults.set(dockCompanionShowsBottomBar, forKey: dockCompanionShowsBottomBarKey)
        defaults.set(dockCompanionOverlayEnabled, forKey: dockCompanionOverlayEnabledKey)
        defaults.set(toggleModifier.rawValue, forKey: toggleModifierKey)
        defaults.set(appOrder, forKey: appOrderKey)
        if let data = try? JSONEncoder().encode(favoriteApps) {
            defaults.set(data, forKey: favoriteAppsKey)
        }
    }
}
