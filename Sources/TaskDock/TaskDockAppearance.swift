import AppKit

/// Only the taskbar panels use a fixed appearance. Other windows follow macOS.
enum TaskDockAppearance {
    static var fixed: NSAppearance? { NSAppearance(named: .darkAqua) }

    static func install() {
        NSApp.appearance = nil
    }
}
