import SwiftUI

enum TaskbarAppearance: String, CaseIterable, Identifiable {
    case light
    case dark

    var id: String { rawValue }
    var label: String { self == .light ? "浅色" : "深色" }
    var colorScheme: ColorScheme { self == .light ? .light : .dark }
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var blacklistedAppKeys: Set<String> { didSet { save() } }
    @Published var showHiddenApps: Bool { didSet { save() } }
    @Published var appearance: TaskbarAppearance { didSet { save() } }

    private let defaults = UserDefaults.standard
    private let blacklistKey = "taskdock.blacklistedAppKeys"
    private let hiddenAppsKey = "taskdock.showHiddenApps"
    private let appearanceKey = "taskdock.appearance"

    init() {
        blacklistedAppKeys = Set(defaults.stringArray(forKey: blacklistKey) ?? [])
        showHiddenApps = defaults.bool(forKey: hiddenAppsKey)
        appearance = TaskbarAppearance(rawValue: defaults.string(forKey: appearanceKey) ?? "dark") ?? .dark
    }

    func toggleBlacklist(for appKey: String) {
        if blacklistedAppKeys.contains(appKey) {
            blacklistedAppKeys.remove(appKey)
        } else {
            blacklistedAppKeys.insert(appKey)
        }
    }

    private func save() {
        defaults.set(Array(blacklistedAppKeys), forKey: blacklistKey)
        defaults.set(showHiddenApps, forKey: hiddenAppsKey)
        defaults.set(appearance.rawValue, forKey: appearanceKey)
    }
}
