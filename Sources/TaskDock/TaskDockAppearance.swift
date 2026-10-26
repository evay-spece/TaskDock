import AppKit

/// TaskDock keeps its current dark appearance regardless of the system setting.
enum TaskDockAppearance {
    static var fixed: NSAppearance? { NSAppearance(named: .darkAqua) }

    static func install() {
        NSApp.appearance = fixed
    }
}
