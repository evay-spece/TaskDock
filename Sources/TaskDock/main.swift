import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: TaskbarPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panelController = TaskbarPanelController()
        panelController?.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        panelController?.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panelController?.restoreFromDock()
        return true
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
