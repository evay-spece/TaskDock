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

    var id: String { rawValue }
    var label: String { self == .taskbar ? "任务栏" : "窗口矩阵" }
    var systemImage: String { self == .taskbar ? "rectangle.bottomthird.inset.filled" : "rectangle.grid.2x2.fill" }
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
    @Published var toggleModifier: TaskbarToggleModifier { didSet { save() } }
    @Published private(set) var appOrder: [String] { didSet { save() } }

    private let defaults = UserDefaults.standard
    private let blacklistKey = "taskdock.blacklistedAppKeys"
    private let hiddenAppsKey = "taskdock.showHiddenApps"
    private let appearanceKey = "taskdock.appearance"
    private let layoutModeKey = "taskdock.layoutMode"
    private let toggleModifierKey = "taskdock.toggleModifier"
    private let appOrderKey = "taskdock.appOrder"

    init() {
        blacklistedAppKeys = Set(defaults.stringArray(forKey: blacklistKey) ?? [])
        showHiddenApps = defaults.bool(forKey: hiddenAppsKey)
        appearance = TaskbarAppearance(rawValue: defaults.string(forKey: appearanceKey) ?? "dark") ?? .dark
        layoutMode = TaskDockLayoutMode(rawValue: defaults.string(forKey: layoutModeKey) ?? "matrix") ?? .matrix
        toggleModifier = TaskbarToggleModifier(rawValue: defaults.string(forKey: toggleModifierKey) ?? "option") ?? .option
        var seenAppKeys = Set<String>()
        appOrder = (defaults.stringArray(forKey: appOrderKey) ?? []).filter {
            seenAppKeys.insert($0).inserted
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

    private func save() {
        defaults.set(Array(blacklistedAppKeys), forKey: blacklistKey)
        defaults.set(showHiddenApps, forKey: hiddenAppsKey)
        defaults.set(appearance.rawValue, forKey: appearanceKey)
        defaults.set(layoutMode.rawValue, forKey: layoutModeKey)
        defaults.set(toggleModifier.rawValue, forKey: toggleModifierKey)
        defaults.set(appOrder, forKey: appOrderKey)
    }
}
