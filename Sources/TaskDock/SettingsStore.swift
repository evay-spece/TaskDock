import AppKit
import SwiftUI

enum TaskbarAppearance: String, CaseIterable, Identifiable {
    case light
    case dark

    var id: String { rawValue }
    var label: String { self == .light ? "浅色" : "深色" }
    var colorScheme: ColorScheme { self == .light ? .light : .dark }
}

enum ModeAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
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
    static let defaultTaskbarHeight: CGFloat = 38
    static let taskbarHeightRange: ClosedRange<CGFloat> = 34...64
    static let defaultTaskbarItemFontSize: CGFloat = 12
    static let taskbarItemFontSizes: [CGFloat] = [8, 9, 10, 11, 12]
    static let recentAppHistoryLimit = 50
    @Published var blacklistedAppKeys: Set<String> { didSet { save() } }
    @Published private(set) var blockedWindowRules: [BlockedWindowRule] { didSet { save() } }
    @Published private(set) var appearanceByMode: [TaskDockLayoutMode: ModeAppearance] { didSet { save() } }
    @Published private(set) var transparencyByMode: [TaskDockLayoutMode: Double] { didSet { save() } }
    @Published private(set) var hiddenAppsByMode: [TaskDockLayoutMode: Bool] { didSet { save() } }
    @Published private(set) var finderTabsByMode: [TaskDockLayoutMode: Bool] { didSet { save() } }
    @Published var showApplicationName: Bool { didSet { save() } }
    @Published var taskItemHighlightStyle: TaskItemHighlightStyle { didSet { save() } }
    @Published var layoutMode: TaskDockLayoutMode { didSet { save() } }
    var showHiddenApps: Bool { showsHiddenApps(in: layoutMode) }
    var finderTabsAsWindows: Bool { showsFinderTabsAsWindows(in: layoutMode) }
    var nonSelectedItemTransparency: Double { transparency(in: layoutMode) }
    var appearance: TaskbarAppearance { resolvedAppearance(in: layoutMode) }
    @Published var activeTaskbarShortcutIndices: Set<Int> = []
    @Published var activeFavoriteShortcutIndices: Set<Int> = []
    @Published var dockCompanionHeight: CGFloat = 39
    @Published var taskbarHeight: CGFloat { didSet { save() } }
    @Published var taskbarItemFontSize: CGFloat { didSet { save() } }
    @Published var taskbarAlignment: TaskbarAlignment { didSet { save() } }
    @Published var taskbarWidthMode: TaskbarWidthMode { didSet { save() } }
    @Published var favoriteMagnificationEnabled: Bool { didSet { save() } }
    @Published private(set) var dockCompanionLeftAppKeys: Set<String> { didSet { save() } }
    @Published private(set) var dockCompanionRightAppKeys: Set<String> { didSet { save() } }
    @Published private(set) var dockCompanionRightAppsCustomized: Bool { didSet { save() } }
    @Published private(set) var dockCompanionAddedApps: [FavoriteApp] { didSet { save() } }
    @Published var dockCompanionMinimumWindowCount: Int { didSet { save() } }
    @Published var dockCompanionCollapseThreshold: Int { didSet { save() } }
    @Published var dockCompanionShowsRecentWindows: Bool { didSet { save() } }
    @Published var dockCompanionShowsBottomBar: Bool { didSet { save() } }
    @Published var dockCompanionOverlayEnabled: Bool { didSet { save() } }
    @Published var toggleModifier: TaskbarToggleModifier { didSet { save() } }
    @Published private(set) var appOrder: [String] { didSet { save() } }
    @Published private(set) var favoriteApps: [FavoriteApp] { didSet { save() } }
    @Published private(set) var recentApps: [FavoriteApp] { didSet { save() } }
    @Published private(set) var favoriteFolders: [FavoriteFolder] { didSet { save() } }
    private var taskbarArrivalOrder = TaskbarArrivalOrder()
    private var taskbarWindowOrderIDs: [String] = []

    private let defaults = UserDefaults.standard
    private let blacklistKey = "taskdock.blacklistedAppKeys"
    private let blockedWindowRulesKey = "taskdock.blockedWindowRules"
    private let hiddenAppsKey = "taskdock.showHiddenApps"
    private let finderTabsAsWindowsKey = "taskdock.finderTabsAsWindows"
    private let showApplicationNameKey = "taskdock.showApplicationName"
    private let nonSelectedItemTransparencyKey = "taskdock.nonSelectedItemTransparency"
    private let taskItemHighlightStyleKey = "taskdock.taskItemHighlightStyle"
    private let appearanceKey = "taskdock.appearance"
    private let layoutModeKey = "taskdock.layoutMode"
    private let taskbarAlignmentKey = "taskdock.taskbarAlignment"
    private let taskbarWidthModeKey = "taskdock.taskbarWidthMode"
    private let taskbarHeightKey = "taskdock.taskbarHeight"
    private let taskbarItemFontSizeKey = "taskdock.taskbarItemFontSize"
    private let favoriteMagnificationEnabledKey = "taskdock.favoriteMagnificationEnabled"
    private let dockCompanionLeftAppKeysKey = "taskdock.dockCompanionLeftAppKeys"
    private let dockCompanionRightAppKeysKey = "taskdock.dockCompanionRightAppKeys"
    private let dockCompanionRightAppsCustomizedKey = "taskdock.dockCompanionRightAppsCustomized"
    private let dockCompanionAddedAppsKey = "taskdock.dockCompanionAddedApps"
    private let dockCompanionMinimumWindowCountKey = "taskdock.dockCompanionMinimumWindowCount"
    private let dockCompanionCollapseThresholdKey = "taskdock.dockCompanionCollapseThreshold"
    private let dockCompanionShowsRecentWindowsKey = "taskdock.dockCompanionShowsRecentWindows"
    private let dockCompanionShowsBottomBarKey = "taskdock.dockCompanionShowsBottomBar"
    private let dockCompanionOverlayEnabledKey = "taskdock.dockCompanionOverlayEnabled"
    private let toggleModifierKey = "taskdock.toggleModifier"
    private let appOrderKey = "taskdock.appOrder"
    private let favoriteAppsKey = "taskdock.favoriteApps"
    private let recentAppsKey = "taskdock.recentApps"
    private let favoriteFoldersKey = "taskdock.favoriteFolders"

    init() {
        blacklistedAppKeys = Set(defaults.stringArray(forKey: blacklistKey) ?? [])
        if let data = defaults.data(forKey: blockedWindowRulesKey),
           let decoded = try? JSONDecoder().decode([BlockedWindowRule].self, from: data) {
            var seenRuleIDs = Set<String>()
            blockedWindowRules = decoded.filter { seenRuleIDs.insert($0.id).inserted }
        } else {
            blockedWindowRules = []
        }
        let legacyHiddenApps = defaults.bool(forKey: hiddenAppsKey)
        let legacyFinderTabs = defaults.bool(forKey: finderTabsAsWindowsKey)
        let legacyTransparency = min(max(defaults.object(forKey: nonSelectedItemTransparencyKey) as? Double ?? 0, 0), 0.7)
        let legacyAppearance = ModeAppearance(rawValue: defaults.string(forKey: appearanceKey) ?? "dark") ?? .dark
        let storedDefaults = UserDefaults.standard
        appearanceByMode = Dictionary(uniqueKeysWithValues: TaskDockLayoutMode.allCases.map { mode in
            let fallback: ModeAppearance = mode == .dockCompanion ? .system : legacyAppearance
            return (mode, ModeAppearance(rawValue: storedDefaults.string(forKey: Self.modeKey(mode, "appearance")) ?? "") ?? fallback)
        })
        transparencyByMode = Dictionary(uniqueKeysWithValues: TaskDockLayoutMode.allCases.map { mode in
            let value = storedDefaults.object(forKey: Self.modeKey(mode, "nonSelectedItemTransparency")) as? Double ?? legacyTransparency
            return (mode, min(max(value, 0), 0.7))
        })
        hiddenAppsByMode = Dictionary(uniqueKeysWithValues: TaskDockLayoutMode.allCases.map { mode in
            (mode, storedDefaults.object(forKey: Self.modeKey(mode, "showHiddenApps")) as? Bool ?? legacyHiddenApps)
        })
        finderTabsByMode = Dictionary(uniqueKeysWithValues: TaskDockLayoutMode.allCases.map { mode in
            (mode, storedDefaults.object(forKey: Self.modeKey(mode, "finderTabsAsWindows")) as? Bool ?? legacyFinderTabs)
        })
        showApplicationName = defaults.object(forKey: showApplicationNameKey) as? Bool ?? true
        taskItemHighlightStyle = TaskItemHighlightStyle(
            rawValue: defaults.string(forKey: taskItemHighlightStyleKey) ?? "white"
        ) ?? .white
        layoutMode = TaskDockLayoutMode(rawValue: defaults.string(forKey: layoutModeKey) ?? "matrix") ?? .matrix
        taskbarAlignment = TaskbarAlignment(rawValue: defaults.string(forKey: taskbarAlignmentKey) ?? "center") ?? .center
        taskbarWidthMode = TaskbarWidthMode(rawValue: defaults.string(forKey: taskbarWidthModeKey) ?? "adaptive") ?? .adaptive
        let savedTaskbarHeight = defaults.object(forKey: taskbarHeightKey) as? Double ?? Double(Self.defaultTaskbarHeight)
        taskbarHeight = min(max(CGFloat(savedTaskbarHeight), Self.taskbarHeightRange.lowerBound), Self.taskbarHeightRange.upperBound)
        let savedFontSize = defaults.object(forKey: taskbarItemFontSizeKey) as? Double ?? Double(Self.defaultTaskbarItemFontSize)
        taskbarItemFontSize = Self.taskbarItemFontSizes.min {
            abs($0 - CGFloat(savedFontSize)) < abs($1 - CGFloat(savedFontSize))
        } ?? Self.defaultTaskbarItemFontSize
        favoriteMagnificationEnabled = defaults.object(forKey: favoriteMagnificationEnabledKey) as? Bool ?? true
        dockCompanionLeftAppKeys = Set(defaults.stringArray(forKey: dockCompanionLeftAppKeysKey) ?? ["com.apple.finder"])
        dockCompanionRightAppKeys = Set(defaults.stringArray(forKey: dockCompanionRightAppKeysKey) ?? [])
        dockCompanionRightAppsCustomized = defaults.bool(forKey: dockCompanionRightAppsCustomizedKey)
        if let data = defaults.data(forKey: dockCompanionAddedAppsKey),
           let decoded = try? JSONDecoder().decode([FavoriteApp].self, from: data) {
            var seenIDs = Set<String>()
            dockCompanionAddedApps = decoded.filter { seenIDs.insert($0.id).inserted }
        } else {
            dockCompanionAddedApps = []
        }
        let savedMinimumWindowCount = defaults.object(forKey: dockCompanionMinimumWindowCountKey) as? Int ?? 2
        dockCompanionMinimumWindowCount = min(max(savedMinimumWindowCount, 1), 20)
        let savedCollapseThreshold = defaults.object(forKey: dockCompanionCollapseThresholdKey) as? Int ?? 3
        dockCompanionCollapseThreshold = min(max(savedCollapseThreshold, 2), 20)
        dockCompanionShowsRecentWindows = defaults.object(forKey: dockCompanionShowsRecentWindowsKey) as? Bool ?? true
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
        if let data = defaults.data(forKey: recentAppsKey),
           let decoded = try? JSONDecoder().decode([FavoriteApp].self, from: data) {
            var seenIDs = Set<String>()
            recentApps = Array(decoded.filter { seenIDs.insert($0.id).inserted }.prefix(Self.recentAppHistoryLimit))
        } else {
            recentApps = []
        }
        if let data = defaults.data(forKey: favoriteFoldersKey),
           let decoded = try? JSONDecoder().decode([FavoriteFolder].self, from: data) {
            var seenPaths = Set<String>()
            favoriteFolders = decoded.filter { seenPaths.insert($0.path).inserted }
        } else {
            let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent("Downloads", isDirectory: true)
            favoriteFolders = [FavoriteFolder(path: downloads.standardizedFileURL.path)]
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

    func reconcileTaskbarOrder(with windows: [WindowModel]) {
        let order = taskbarArrivalOrder.reconcile(
            windows.map { .init(id: $0.id, appKey: $0.appKey) },
            appOrder: appOrder
        )
        if order.apps != appOrder { appOrder = order.apps }
        taskbarWindowOrderIDs = order.windows
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

    func recordRecentApp(_ app: FavoriteApp) {
        let updated = [app] + recentApps.filter { $0.id != app.id }
        let limited = Array(updated.prefix(Self.recentAppHistoryLimit))
        if limited != recentApps { recentApps = limited }
    }

    @discardableResult
    func addFavoriteFolder(_ url: URL) -> Bool {
        let standardized = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard standardized.isFileURL,
              FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              !favoriteFolders.contains(where: { $0.path == standardized.path }) else { return false }
        favoriteFolders.append(FavoriteFolder(path: standardized.path))
        return true
    }

    func removeFavoriteFolder(_ folder: FavoriteFolder) {
        favoriteFolders.removeAll { $0.id == folder.id }
    }

    func reorderFavorites(_ orderedIDs: [String]) {
        guard orderedIDs.count == favoriteApps.count,
              Set(orderedIDs) == Set(favoriteApps.map(\.id)) else { return }
        let favoritesByID = Dictionary(uniqueKeysWithValues: favoriteApps.map { ($0.id, $0) })
        let reordered = orderedIDs.compactMap { favoritesByID[$0] }
        guard reordered != favoriteApps else { return }
        favoriteApps = reordered
    }

    func orderedWindows(_ windows: [WindowModel]) -> [WindowModel] {
        let order = Dictionary(
            appOrder.enumerated().map { ($1, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let windowOrder = Dictionary(
            taskbarWindowOrderIDs.enumerated().map { ($1, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return windows.enumerated().sorted { lhs, rhs in
            let lhsOrder = order[lhs.element.appKey] ?? Int.max
            let rhsOrder = order[rhs.element.appKey] ?? Int.max
            if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
            if layoutMode == .taskbar {
                let lhsWindowOrder = windowOrder[lhs.element.id] ?? Int.max
                let rhsWindowOrder = windowOrder[rhs.element.id] ?? Int.max
                if lhsWindowOrder != rhsWindowOrder { return lhsWindowOrder < rhsWindowOrder }
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
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

    @discardableResult
    func addDockCompanionApp(applicationURL: URL, side: DockCompanionAppSide, availableAppKeys: Set<String>) -> Bool {
        let url = applicationURL.standardizedFileURL
        guard url.pathExtension.lowercased() == "app",
              let bundle = Bundle(url: url),
              bundle.infoDictionary != nil else { return false }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let bundleIdentifier = bundle.bundleIdentifier
        let appKey = bundleIdentifier ?? "name:\(name)"
        let wasAdded = dockCompanionAddedApps.contains { $0.id == appKey }
        let previousSide = dockCompanionSide(for: appKey, availableAppKeys: availableAppKeys)
        if !wasAdded {
            dockCompanionAddedApps.append(FavoriteApp(
                id: appKey,
                bundleIdentifier: bundleIdentifier,
                applicationName: name,
                bundlePath: url.path
            ))
        }
        switch side {
        case .left:
            setDockCompanionLeft(true, appKey: appKey)
        case .right:
            setDockCompanionRight(true, appKey: appKey, availableAppKeys: availableAppKeys.union([appKey]))
        case .hidden:
            break
        }
        return !wasAdded || previousSide != side
    }

    private static func modeKey(_ mode: TaskDockLayoutMode, _ field: String) -> String {
        "taskdock.mode.\(mode.rawValue).\(field)"
    }

    func appearancePreference(in mode: TaskDockLayoutMode) -> ModeAppearance {
        appearanceByMode[mode] ?? .system
    }

    func setAppearance(_ value: ModeAppearance, in mode: TaskDockLayoutMode) {
        guard appearanceByMode[mode] != value else { return }
        appearanceByMode[mode] = value
    }

    func resolvedAppearance(in mode: TaskDockLayoutMode) -> TaskbarAppearance {
        switch appearancePreference(in: mode) {
        case .light: return .light
        case .dark: return .dark
        case .system:
            return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
        }
    }

    func transparency(in mode: TaskDockLayoutMode) -> Double {
        transparencyByMode[mode] ?? 0
    }

    func setTransparency(_ value: Double, in mode: TaskDockLayoutMode) {
        let clamped = min(max(value, 0), 0.7)
        guard transparencyByMode[mode] != clamped else { return }
        transparencyByMode[mode] = clamped
    }

    func showsHiddenApps(in mode: TaskDockLayoutMode) -> Bool {
        hiddenAppsByMode[mode] ?? false
    }

    func setShowsHiddenApps(_ value: Bool, in mode: TaskDockLayoutMode) {
        guard hiddenAppsByMode[mode] != value else { return }
        hiddenAppsByMode[mode] = value
    }

    func showsFinderTabsAsWindows(in mode: TaskDockLayoutMode) -> Bool {
        finderTabsByMode[mode] ?? false
    }

    func setShowsFinderTabsAsWindows(_ value: Bool, in mode: TaskDockLayoutMode) {
        guard finderTabsByMode[mode] != value else { return }
        finderTabsByMode[mode] = value
    }

    private func save() {
        defaults.set(Array(blacklistedAppKeys), forKey: blacklistKey)
        if let data = try? JSONEncoder().encode(blockedWindowRules) {
            defaults.set(data, forKey: blockedWindowRulesKey)
        }
        defaults.set(showApplicationName, forKey: showApplicationNameKey)
        defaults.set(taskItemHighlightStyle.rawValue, forKey: taskItemHighlightStyleKey)
        for mode in TaskDockLayoutMode.allCases {
            defaults.set(appearancePreference(in: mode).rawValue, forKey: Self.modeKey(mode, "appearance"))
            defaults.set(transparency(in: mode), forKey: Self.modeKey(mode, "nonSelectedItemTransparency"))
            defaults.set(showsHiddenApps(in: mode), forKey: Self.modeKey(mode, "showHiddenApps"))
            defaults.set(showsFinderTabsAsWindows(in: mode), forKey: Self.modeKey(mode, "finderTabsAsWindows"))
        }
        defaults.set(layoutMode.rawValue, forKey: layoutModeKey)
        defaults.set(taskbarAlignment.rawValue, forKey: taskbarAlignmentKey)
        defaults.set(taskbarWidthMode.rawValue, forKey: taskbarWidthModeKey)
        defaults.set(Double(taskbarHeight), forKey: taskbarHeightKey)
        defaults.set(Double(taskbarItemFontSize), forKey: taskbarItemFontSizeKey)
        defaults.set(favoriteMagnificationEnabled, forKey: favoriteMagnificationEnabledKey)
        defaults.set(Array(dockCompanionLeftAppKeys), forKey: dockCompanionLeftAppKeysKey)
        defaults.set(Array(dockCompanionRightAppKeys), forKey: dockCompanionRightAppKeysKey)
        defaults.set(dockCompanionRightAppsCustomized, forKey: dockCompanionRightAppsCustomizedKey)
        if let data = try? JSONEncoder().encode(dockCompanionAddedApps) {
            defaults.set(data, forKey: dockCompanionAddedAppsKey)
        }
        defaults.set(dockCompanionMinimumWindowCount, forKey: dockCompanionMinimumWindowCountKey)
        defaults.set(dockCompanionCollapseThreshold, forKey: dockCompanionCollapseThresholdKey)
        defaults.set(dockCompanionShowsRecentWindows, forKey: dockCompanionShowsRecentWindowsKey)
        defaults.set(dockCompanionShowsBottomBar, forKey: dockCompanionShowsBottomBarKey)
        defaults.set(dockCompanionOverlayEnabled, forKey: dockCompanionOverlayEnabledKey)
        defaults.set(toggleModifier.rawValue, forKey: toggleModifierKey)
        defaults.set(appOrder, forKey: appOrderKey)
        if let data = try? JSONEncoder().encode(favoriteApps) {
            defaults.set(data, forKey: favoriteAppsKey)
        }
        if let data = try? JSONEncoder().encode(recentApps) {
            defaults.set(data, forKey: recentAppsKey)
        }
        if let data = try? JSONEncoder().encode(favoriteFolders) {
            defaults.set(data, forKey: favoriteFoldersKey)
        }
    }
}
