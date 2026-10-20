import AppKit
import SwiftUI

@MainActor
final class TaskDockLicenseWindowController: NSWindowController {
    init(license: LicenseService) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 350, height: 580),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "TaskDock 购买与激活"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: LicensePopoverView(license: license))
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { return nil }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
