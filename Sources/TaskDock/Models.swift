import AppKit
import ApplicationServices

struct FavoriteApp: Identifiable, Codable, Hashable {
    let id: String
    let bundleIdentifier: String?
    let applicationName: String
    let bundlePath: String?
}

struct WindowModel: Identifiable, Hashable {
    let id: String
    let pid: pid_t
    let bundleIdentifier: String?
    let applicationName: String
    let applicationIcon: NSImage?
    let title: String
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
