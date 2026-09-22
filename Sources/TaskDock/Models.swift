import AppKit
import ApplicationServices

struct FavoriteApp: Identifiable, Codable, Hashable {
    let id: String
    let bundleIdentifier: String?
    let applicationName: String
    let bundlePath: String?
}

struct BlockedWindowRule: Identifiable, Codable, Hashable {
    let appKey: String
    let applicationName: String
    let rawTitle: String
    let accessibilityRole: String
    let accessibilitySubrole: String?

    var id: String {
        [appKey, rawTitle, accessibilityRole, accessibilitySubrole ?? ""]
            .joined(separator: "\u{1F}")
    }

    var windowLabel: String {
        rawTitle.isEmpty ? "无标题窗口" : rawTitle
    }

    init(
        appKey: String,
        applicationName: String,
        rawTitle: String,
        accessibilityRole: String,
        accessibilitySubrole: String?
    ) {
        self.appKey = appKey
        self.applicationName = applicationName
        self.rawTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        self.accessibilityRole = accessibilityRole
        self.accessibilitySubrole = accessibilitySubrole
    }

    init(window: WindowModel) {
        self.init(
            appKey: window.appKey,
            applicationName: window.applicationName,
            rawTitle: window.rawTitle,
            accessibilityRole: window.accessibilityRole,
            accessibilitySubrole: window.accessibilitySubrole
        )
    }

    func matches(
        appKey: String,
        rawTitle: String,
        accessibilityRole: String,
        accessibilitySubrole: String?
    ) -> Bool {
        self.appKey == appKey &&
            self.rawTitle == rawTitle.trimmingCharacters(in: .whitespacesAndNewlines) &&
            self.accessibilityRole == accessibilityRole &&
            self.accessibilitySubrole == accessibilitySubrole
    }
}

struct WindowModel: Identifiable, Hashable {
    let id: String
    let pid: pid_t
    let bundleIdentifier: String?
    let applicationName: String
    let applicationIcon: NSImage?
    let rawTitle: String
    let title: String
    let accessibilityRole: String
    let accessibilitySubrole: String?
    let isMinimized: Bool
    let isFocused: Bool
    let isMain: Bool
    let axWindow: AXUIElement

    var appKey: String { bundleIdentifier ?? "name:\(applicationName)" }

    static func == (lhs: WindowModel, rhs: WindowModel) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.isMinimized == rhs.isMinimized &&
        lhs.isFocused == rhs.isFocused &&
        lhs.isMain == rhs.isMain
    }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
