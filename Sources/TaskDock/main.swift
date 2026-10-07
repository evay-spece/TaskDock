import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var panelController: TaskbarPanelController?
    private var statusItem: NSStatusItem?
    private let statusMenu = NSMenu()
    private let updateChecker = UpdateChecker.shared
    private var updateWindowController: UpdateProgressWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ReleaseDefaults101.applyIfNeeded()
        panelController = TaskbarPanelController()
        panelController?.show()
        configureStatusItem()
        updateChecker.check()
    }

    func applicationWillTerminate(_ notification: Notification) {
        panelController?.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panelController?.restoreFromDock()
        return true
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateChecker.checkIfNeeded()
        rebuildStatusMenu()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: "TaskDock")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "TaskDock"
        }
        statusMenu.delegate = self
        item.menu = statusMenu
        statusItem = item
        rebuildStatusMenu()
    }

    private func rebuildStatusMenu() {
        statusMenu.removeAllItems()

        let canRestore = panelController?.canRestoreMinimizedWindows == true
        let minimizeItem = NSMenuItem(
            title: canRestore ? "恢复刚才最小化的窗口" : "最小化全部窗口",
            action: #selector(minimizeAllWindows), keyEquivalent: ""
        )
        minimizeItem.image = NSImage(
            systemSymbolName: canRestore ? "rectangle.stack" : "minus.rectangle",
            accessibilityDescription: nil
        )
        minimizeItem.target = self
        statusMenu.addItem(minimizeItem)

        let modeItem = NSMenuItem(title: "显示模式", action: nil, keyEquivalent: "")
        modeItem.image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: nil)
        let modeMenu = NSMenu(title: "显示模式")
        for mode in TaskDockLayoutMode.allCases {
            let item = NSMenuItem(title: mode.label, action: #selector(selectLayoutMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.image = NSImage(systemSymbolName: mode.systemImage, accessibilityDescription: nil)
            item.state = panelController?.currentLayoutMode == mode ? .on : .off
            modeMenu.addItem(item)
        }
        modeItem.submenu = modeMenu
        statusMenu.addItem(modeItem)

        let settingsItem = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        settingsItem.target = self
        statusMenu.addItem(settingsItem)

        let updateAvailable: Bool
        if case .updateAvailable = updateChecker.status {
            updateAvailable = true
        } else {
            updateAvailable = false
        }
        let updateItem = NSMenuItem(title: "检查更新", action: #selector(checkForUpdates), keyEquivalent: "")
        if updateAvailable {
            let title = NSMutableAttributedString(string: "检查更新  ")
            title.append(NSAttributedString(string: "●", attributes: [.foregroundColor: NSColor.systemRed]))
            updateItem.attributedTitle = title
            updateItem.setAccessibilityLabel("检查更新，有新版本")
        }
        updateItem.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)
        updateItem.target = self
        statusMenu.addItem(updateItem)

        statusMenu.addItem(.separator())

        let isHidden = panelController?.isTaskDockHidden == true
        let visibilityItem = NSMenuItem(
            title: isHidden ? "显示 TaskDock" : "隐藏 TaskDock",
            action: isHidden ? #selector(showTaskDock) : #selector(hideTaskDock),
            keyEquivalent: ""
        )
        visibilityItem.image = NSImage(
            systemSymbolName: isHidden ? "eye" : "eye.slash",
            accessibilityDescription: nil
        )
        visibilityItem.target = self
        statusMenu.addItem(visibilityItem)

        let quitItem = NSMenuItem(title: "退出 TaskDock", action: #selector(quitTaskDock), keyEquivalent: "q")
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        quitItem.target = self
        statusMenu.addItem(quitItem)
    }

    @objc private func minimizeAllWindows() {
        panelController?.minimizeAllWindows()
    }

    @objc private func selectLayoutMode(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let mode = TaskDockLayoutMode(rawValue: rawValue) else { return }
        panelController?.setLayoutMode(mode)
    }

    @objc private func openSettings() {
        panelController?.presentSettings()
    }

    @objc private func checkForUpdates() {
        if updateWindowController == nil {
            updateWindowController = UpdateProgressWindowController(checker: updateChecker)
        }
        updateWindowController?.showWindow(nil)
        updateWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        updateChecker.checkAndInstall()
    }

    @objc private func hideTaskDock() {
        panelController?.hideTaskDock()
    }

    @objc private func showTaskDock() {
        panelController?.showTaskDock()
    }

    @objc private func quitTaskDock() {
        NSApp.terminate(nil)
    }
}

let application = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
application.delegate = delegate
application.run()
