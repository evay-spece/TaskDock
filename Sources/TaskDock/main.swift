import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var panelController: TaskbarPanelController?
    private var statusItem: NSStatusItem?
    private let statusMenu = NSMenu()
    private let updateChecker = UpdateChecker.shared
    private let license = LicenseService()
    private var licenseWindowController: TaskDockLicenseWindowController?
    private var updateWindowController: UpdateProgressWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureApplicationMenu()
        Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            UpdateSupport.archiveLegacyBackups()
        }
        ReleaseDefaults101.applyIfNeeded()
        license.start()
        panelController = TaskbarPanelController(license: license, onOpenLicense: { [weak self] in
            self?.openLicense()
        })
        panelController?.show()
        configureStatusItem()
        updateChecker.check()
        if ProcessInfo.processInfo.arguments.contains("--show-settings") {
            panelController?.presentSettings()
        }
        if ProcessInfo.processInfo.arguments.contains("--show-license") {
            openLicense()
        }
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

    private func configureApplicationMenu() {
        // Accessory apps still need an Edit menu for AppKit to route Command-V,
        // Command-C and Command-A to the focused field editor or NSTextView.
        let menu = NSMenu()
        let applicationItem = NSMenuItem(title: "TaskDock", action: nil, keyEquivalent: "")
        let applicationMenu = NSMenu(title: "TaskDock")
        let settingsItem = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        applicationMenu.addItem(settingsItem)
        applicationMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出 TaskDock", action: #selector(quitTaskDock), keyEquivalent: "q")
        quitItem.target = self
        applicationMenu.addItem(quitItem)
        applicationItem.submenu = applicationMenu
        menu.addItem(applicationItem)

        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        menu.addItem(editItem)
        NSApp.mainMenu = menu
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

        if !license.activatedLicenseCode.isEmpty || LicenseStatus.hasValidPurchase || !license.isUnlocked {
            let days = license.remainingDays
            let trialItem = NSMenuItem(
                title: (license.activatedLicenseCode.isEmpty && !LicenseStatus.hasValidPurchase) ?
                    (days > 0 ? "试用剩余 \(days) 天" : "试用已结束") : "已购买授权",
                action: nil, keyEquivalent: ""
            )
            trialItem.image = NSImage(systemSymbolName: "clock", accessibilityDescription: nil)
            trialItem.isEnabled = false
            statusMenu.addItem(trialItem)

        }

        let purchaseItem = NSMenuItem(title: "购买与激活…", action: #selector(openLicense), keyEquivalent: "")
        purchaseItem.image = NSImage(systemSymbolName: "key", accessibilityDescription: nil)
        purchaseItem.target = self
        statusMenu.addItem(purchaseItem)

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

    @objc private func openLicense() {
        if licenseWindowController == nil {
            licenseWindowController = TaskDockLicenseWindowController(license: license)
        }
        licenseWindowController?.present()
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
