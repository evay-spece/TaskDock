import AppKit
import ApplicationServices

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

    static func == (lhs: WindowModel, rhs: WindowModel) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
