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
    private var updateReminderWindowController: UpdateReminderWindowController?
    private let majorMinorReminderKey = "taskdock.lastMajorMinorUpdateReminder"
    private let finderFileHotkeys = FinderCutHotkey()
    private var pendingFileURL: URL?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(openFileURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        FileTypeSettings.migrateLegacyIfNeeded()
        finderFileHotkeys.start()
        NotificationCenter.default.addObserver(self, selector: #selector(testFinderCut),
                                               name: .taskDockTestFinderCut, object: nil)
        configureApplicationMenu()
        Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            UpdateSupport.archiveLegacyBackups()
        }
        ReleaseDefaults101.applyIfNeeded()
        ReleaseDefaults170.applyIfNeeded()
        EasterEggSettingsEntryReset.applyIfNeeded(
            build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        )
        license.start()
        panelController = TaskbarPanelController(license: license, onOpenLicense: { [weak self] in
            self?.openLicense()
        })
        panelController?.show()
        configureStatusItem()
        updateChecker.onAutomaticMajorMinorUpdateAvailable = { [weak self] update in
            self?.showMajorMinorUpdateReminder(update)
        }
        updateChecker.check(automatic: true)
        if ProcessInfo.processInfo.arguments.contains("--show-settings") {
            panelController?.presentSettings()
        }
        if ProcessInfo.processInfo.arguments.contains("--show-license") {
            openLicense()
        }
        if let pendingFileURL {
            self.pendingFileURL = nil
            handleFileURL(pendingFileURL)
        }
    }

    @objc private func openFileURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let raw = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: raw), url.scheme == "taskdockfile" else { return }
        guard panelController != nil else { pendingFileURL = url; return }
        handleFileURL(url)
    }

    private func handleFileURL(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        if components.host == "settings" {
            guard FileTypeSettings.isEntryVisible else { return }
            panelController?.presentSettings()
            NotificationCenter.default.post(name: .taskDockOpenFileSettings, object: nil)
            return
        }
        guard FileTypeSettings.isEnabled,
              let folderPath = components.queryItems?.first(where: { $0.name == "folder" })?.value else { return }
        let folder = URL(fileURLWithPath: folderPath, isDirectory: true)
        do {
            let result: [URL]
            switch components.host {
            case "create":
                guard let id = components.queryItems?.first(where: { $0.name == "kind" })?.value,
                      let entry = FileTypeSettings.load().first(where: { $0.id == id && $0.enabled }) else { return }
                result = [try FileCreator.create(entry, in: folder)]
            case "move":
                result = try ClipboardCutter.move(to: folder)
            default:
                return
            }
            NSWorkspace.shared.activateFileViewerSelecting(result)
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = components.host == "move" ? "无法粘贴并移动" : "无法新建文件"
            alert.informativeText = error.localizedDescription
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    @objc private func testFinderCut() {
        guard FileTypeSettings.isEnabled else { return }
        let status = finderFileHotkeys.testFinderSelection()
        let alert = NSAlert()
        alert.messageText = status.hasPrefix("items ") ? "剪切快捷键已就绪" : "剪切快捷键需要检查"
        alert.informativeText = status.hasPrefix("items ")
            ? "Finder 选中的文件已标记为剪切。到目标文件夹按 ⌘V，或右键选择“粘贴并移动”。"
            : "请先在 Finder 选中测试文件，并允许 TaskDock 控制 Finder。诊断：\(status)"
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    func applicationWillTerminate(_ notification: Notification) {
        panelController?.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if license.isUnlocked || LicenseStatus.hasValidPurchase {
            panelController?.restoreFromDock()
        } else {
            openLicense()
        }
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

        let canRestore = panelController?.canRestoreHiddenApplications == true
        let minimizeItem = NSMenuItem(
            title: canRestore ? "恢复刚才隐藏的 App" : "隐藏全部 App",
            action: #selector(toggleAllApplications), keyEquivalent: ""
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

    @objc private func toggleAllApplications() {
        panelController?.toggleAllApplications()
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

    private func showMajorMinorUpdateReminder(_ update: UpdateChecker.AvailableUpdate) {
        let lastReminded = UserDefaults.standard.string(forKey: majorMinorReminderKey)
        guard updateReminderWindowController?.window?.isVisible != true,
              UpdateSupport.shouldRemindForMajorMinorUpgrade(
                  update.version, than: updateChecker.currentVersion, lastReminded: lastReminded
              ),
              let upgradeID = UpdateSupport.majorMinorUpgradeID(
                  update.version, than: updateChecker.currentVersion
              ) else { return }

        let controller = UpdateReminderWindowController(
            currentVersion: updateChecker.currentVersion,
            newVersion: update.version,
            onUpdate: { [weak self] in
                self?.updateReminderWindowController?.close()
                self?.checkForUpdates()
            },
            onLater: { [weak self] in self?.updateReminderWindowController?.close() }
        )
        updateReminderWindowController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        UserDefaults.standard.set(upgradeID, forKey: majorMinorReminderKey)
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

extension Notification.Name {
    static let taskDockOpenFileSettings = Notification.Name("TaskDockOpenFileSettings")
    static let taskDockTestFinderCut = Notification.Name("TaskDockTestFinderCut")
}

TaskbarExperimentalGlass.installPreferenceIsolation()
let application = NSApplication.shared
TaskDockAppearance.install()
let delegate = MainActor.assumeIsolated { AppDelegate() }
application.delegate = delegate
application.run()
