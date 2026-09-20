import AppKit
import SwiftUI

@MainActor
final class TaskbarPanelController {
    private let permissionService = AccessibilityPermissionService()
    private let windowService = AXWindowService()
    private let settings = SettingsStore()
    private var panel: NSPanel?
    private var timer: Timer?
    private var windows: [WindowModel] = []
    private var hostingView: NSHostingView<TaskbarView>?
    private var settingsWindowController: SettingsWindowController?

    func show() {
        let view = TaskbarView(
            windows: windows,
            isAccessibilityTrusted: permissionService.isTrusted,
            onRequestPermission: { [weak self] in self?.requestPermission() },
            onRefresh: { [weak self] in self?.refresh() },
            onSelect: { [weak self] window in self?.select(window) },
            onShowAppWindows: { [weak self] window in self?.showAppWindows(for: window) },
            onClose: { [weak self] window in self?.close(window) },
            settings: settings,
            onSettingsChanged: { [weak self] in self?.refresh() },
            onOpenSettings: { [weak self] in self?.openSettings() }
        )
        let hosting = NSHostingView(rootView: view)
        hostingView = hosting
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.contentView = hosting
        self.panel = panel
        reposition()
        panel.orderFrontRegardless()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(workspaceChanged), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(workspaceChanged), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
    }

    func stop() {
        timer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        panel?.orderOut(nil)
    }

    private func reposition() {
        guard let screen = NSScreen.screens.first, let panel else { return }
        let width = screen.visibleFrame.width * 0.8
        let height: CGFloat = 68
        let frame = NSRect(x: screen.visibleFrame.midX - width / 2, y: screen.visibleFrame.minY + 12, width: width, height: height)
        panel.setFrame(frame, display: true)
    }

    private func refresh() {
        windows = windowService.enumerateWindows(
            excludingPID: ProcessInfo.processInfo.processIdentifier,
            showHiddenApps: settings.showHiddenApps,
            blacklistedAppKeys: settings.blacklistedAppKeys
        )
        hostingView?.rootView = TaskbarView(
            windows: windows,
            isAccessibilityTrusted: permissionService.isTrusted,
            onRequestPermission: { [weak self] in self?.requestPermission() },
            onRefresh: { [weak self] in self?.refresh() },
            onSelect: { [weak self] window in self?.select(window) },
            onShowAppWindows: { [weak self] window in self?.showAppWindows(for: window) },
            onClose: { [weak self] window in self?.close(window) },
            settings: settings,
            onSettingsChanged: { [weak self] in self?.refresh() },
            onOpenSettings: { [weak self] in self?.openSettings() }
        )
        panel?.orderFrontRegardless()
        reposition()
    }

    private func requestPermission() { permissionService.requestAccess(); refresh() }
    private func select(_ window: WindowModel) { _ = windowService.activate(window); refresh() }
    private func showAppWindows(for window: WindowModel) {
        windowService.showAllWindows(for: window.pid, from: windows)
        refresh()
    }
    private func close(_ window: WindowModel) {
        _ = windowService.close(window)
        refresh()
    }
    private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(settings: settings, windows: windows) { [weak self] in
                self?.refresh()
            }
        }
        settingsWindowController?.update(windows: windows)
        settingsWindowController?.show()
    }

    @objc private func workspaceChanged() { refresh() }
}
