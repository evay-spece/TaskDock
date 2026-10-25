import AppKit
import SwiftUI

enum TaskDockAppearanceMode: String, CaseIterable, Identifiable {
    case light, dark, system
    var id: String { rawValue }
    var title: String {
        switch self {
        case .light: return "浅色"
        case .dark: return "深色"
        case .system: return "跟随系统"
        }
    }
    var appearance: NSAppearance? {
        switch self {
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        case .system: return nil
        }
    }
}

enum AppAppearanceSettings {
    static let preferenceKey = "taskdock.appearanceModeV1"
    private static var observer: NSObjectProtocol?
    private static var appliedMode: TaskDockAppearanceMode?

    static func install() {
        apply()
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { _ in apply() }
    }

    static func apply() {
        let mode = TaskDockAppearanceMode(rawValue:
            UserDefaults.standard.string(forKey: preferenceKey) ?? "") ?? .system
        guard mode != appliedMode else { return }
        appliedMode = mode
        NSApp.appearance = mode.appearance
    }
}

struct AppAppearanceSettingsView: View {
    @AppStorage(AppAppearanceSettings.preferenceKey) private var mode = TaskDockAppearanceMode.system.rawValue
    var body: some View {
        Picker("外观模式", selection: $mode) {
            ForEach(TaskDockAppearanceMode.allCases) { mode in
                Text(mode.title).tag(mode.rawValue)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: mode) { _ in AppAppearanceSettings.apply() }
    }
}
