import AppKit
import SwiftUI

enum TaskbarAppearance: String, CaseIterable, Identifiable {
    case light
    case dark

    var id: String { rawValue }
    var label: String { self == .light ? "浅色" : "深色" }
    var colorScheme: ColorScheme { self == .light ? .light : .dark }
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
    @Published var showHiddenApps: Bool { didSet { save() } }
    @Published var appearance: TaskbarAppearance { didSet { save() } }
    @Published var layoutMode: TaskDockLayoutMode { didSet { save() } }
    @Published var dockCompanionHeight: CGFloat = 39
    @Published var taskbarAlignment: TaskbarAlignment { didSet { save() } }
    @Published var toggleModifier: TaskbarToggleModifier { didSet { save() } }
    @Published private(set) var appOrder: [String] { didSet { save() } }
    @Published private(set) var favoriteApps: [FavoriteApp] { didSet { save() } }

    private let defaults = UserDefaults.standard
    private let blacklistKey = "taskdock.blacklistedAppKeys"
    private let hiddenAppsKey = "taskdock.showHiddenApps"
    private let appearanceKey = "taskdock.appearance"
    private let layoutModeKey = "taskdock.layoutMode"
    private let taskbarAlignmentKey = "taskdock.taskbarAlignment"
    private let toggleModifierKey = "taskdock.toggleModifier"
    private let appOrderKey = "taskdock.appOrder"
    private let favoriteAppsKey = "taskdock.favoriteApps"

    init() {
        blacklistedAppKeys = Set(defaults.stringArray(forKey: blacklistKey) ?? [])
        showHiddenApps = defaults.bool(forKey: hiddenAppsKey)
        appearance = TaskbarAppearance(rawValue: defaults.string(forKey: appearanceKey) ?? "dark") ?? .dark
        layoutMode = TaskDockLayoutMode(rawValue: defaults.string(forKey: layoutModeKey) ?? "matrix") ?? .matrix
        taskbarAlignment = TaskbarAlignment(rawValue: defaults.string(forKey: taskbarAlignmentKey) ?? "center") ?? .center
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

    func removeFavorite(_ favorite: FavoriteApp) {
        favoriteApps.removeAll { $0.id == favorite.id }
    }

    private func save() {
        defaults.set(Array(blacklistedAppKeys), forKey: blacklistKey)
        defaults.set(showHiddenApps, forKey: hiddenAppsKey)
        defaults.set(appearance.rawValue, forKey: appearanceKey)
        defaults.set(layoutMode.rawValue, forKey: layoutModeKey)
        defaults.set(taskbarAlignment.rawValue, forKey: taskbarAlignmentKey)
        defaults.set(toggleModifier.rawValue, forKey: toggleModifierKey)
        defaults.set(appOrder, forKey: appOrderKey)
        if let data = try? JSONEncoder().encode(favoriteApps) {
            defaults.set(data, forKey: favoriteAppsKey)
        }
    }
}
