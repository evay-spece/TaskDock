import AppKit
import SwiftUI

@MainActor
final class TaskbarPanelController {
    private struct AppFocusObserver {
        let observer: AXObserver
        let application: AXUIElement
    }

    private let permissionService = AccessibilityPermissionService()
    private let windowService = AXWindowService()
    private let settings = SettingsStore()
    private var panel: NSPanel?
    private var timer: Timer?
    private var windows: [WindowModel] = []
    private var hostingView: NSHostingView<TaskbarView>?
    private var settingsWindowController: SettingsWindowController?
    private var reorderRefreshPauseUntil: Date?
    private var panelDragStartOrigin: NSPoint?
    private var customPanelOrigins: [TaskDockLayoutMode: NSPoint] = [:]
    private var isHiddenInDock = false
    private var dockRestoreAvailableAt = Date.distantPast
    private var shortcutMonitor: ModifierDoubleTapMonitor?
    private var lastRenderedWindowSignature = ""
    private var appFocusObservers: [pid_t: AppFocusObserver] = [:]

    private static let focusObserverCallback: AXObserverCallback = { _, _, _, context in
        guard let context else { return }
        let controller = Unmanaged<TaskbarPanelController>.fromOpaque(context).takeUnretainedValue()
        Task { @MainActor [weak controller] in
            controller?.refresh()
        }
    }

    func show() {
        let view = TaskbarView(
            windows: windows,
            isAccessibilityTrusted: permissionService.isTrusted,
            onRequestPermission: { [weak self] in self?.requestPermission() },
            onSelect: { [weak self] window in self?.select(window) },
            onMinimizeAll: { [weak self] in self?.minimizeAll() },
            onShowAppWindows: { [weak self] window in self?.showAppWindows(for: window) },
            onClose: { [weak self] window in self?.close(window) },
            settings: settings,
            onSettingsChanged: { [weak self] in self?.refresh() },
            onOpenSettings: { [weak self] in self?.openSettings() },
            onAppDragChanged: { [weak self] isDragging in self?.setAppReordering(isDragging) },
            onPanelDragChanged: { [weak self] translation in self?.movePanel(by: translation) },
            onPanelDragEnded: { [weak self] in self?.finishPanelDrag() },
            onHideTaskbar: { [weak self] in self?.hideInDock() },
            onQuit: { NSApp.terminate(nil) }
        )
        let hosting = NSHostingView(rootView: view)
        hostingView = hosting
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.contentView = hosting
        self.panel = panel
        shortcutMonitor = ModifierDoubleTapMonitor(settings: settings) { [weak self] in
            self?.toggleTaskbarVisibility()
        }
        shortcutMonitor?.start()
        reposition()
        panel.orderFrontRegardless()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.automaticRefresh() }
        }
        let workspaceNotifications = NSWorkspace.shared.notificationCenter
        workspaceNotifications.addObserver(self, selector: #selector(workspaceChanged), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        workspaceNotifications.addObserver(self, selector: #selector(workspaceChanged), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        workspaceNotifications.addObserver(self, selector: #selector(workspaceChanged), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        workspaceNotifications.addObserver(self, selector: #selector(workspaceChanged), name: NSWorkspace.didHideApplicationNotification, object: nil)
        workspaceNotifications.addObserver(self, selector: #selector(workspaceChanged), name: NSWorkspace.didUnhideApplicationNotification, object: nil)
        syncAppFocusObservers()
    }

    func stop() {
        timer?.invalidate()
        shortcutMonitor?.stop()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        removeAllAppFocusObservers()
        windowService.clearWindowSpaceReservations(restore: true, windows: windows)
        panel?.orderOut(nil)
    }

    func restoreFromDock() {
        guard isHiddenInDock, Date() >= dockRestoreAvailableAt else { return }
        isHiddenInDock = false
        NSApp.setActivationPolicy(.accessory)
        refresh()
        panel?.orderFrontRegardless()
    }

    private func reposition() {
        guard let screen = NSScreen.screens.first, panel != nil else { return }
        let screenFrame = screen.visibleFrame

        if settings.layoutMode == .taskbar {
            let preferredItemWidth: CGFloat = 220
            let controlsAndPadding: CGFloat = 184
            let itemSpacing = CGFloat(max(windows.count - 1, 0)) * 4
            let desiredWidth: CGFloat
            if !permissionService.isTrusted {
                desiredWidth = 600
            } else if windows.isEmpty {
                desiredWidth = 390
            } else {
                desiredWidth = CGFloat(windows.count) * preferredItemWidth + itemSpacing + controlsAndPadding
            }
            let width = min(screenFrame.width - 24, desiredWidth)
            let height: CGFloat = 38
            let defaultOrigin = NSPoint(x: screenFrame.midX - width / 2, y: screenFrame.minY + 4)
            let proposedOrigin = customPanelOrigins[.taskbar] ?? defaultOrigin
            let maxX = max(screenFrame.minX, screenFrame.maxX - width)
            let maxY = max(screenFrame.minY, screenFrame.maxY - height)
            let origin = NSPoint(
                x: min(max(proposedOrigin.x, screenFrame.minX), maxX),
                y: min(max(proposedOrigin.y, screenFrame.minY), maxY)
            )
            setPanelFrameIfNeeded(NSRect(origin: origin, size: NSSize(width: width, height: height)))
            return
        }

        let appGroups = Dictionary(grouping: windows, by: \.appKey)
        let appCount = max(appGroups.count, 1)
        let maxWindowCount = max(appGroups.values.map(\.count).max() ?? 1, 1)
        let groupSpacing = CGFloat(max(appCount - 1, 0)) * 6
        let controlsWidth: CGFloat = 160
        let preferredColumnWidth: CGFloat = 180
        let maxWidth = screenFrame.width - 24
        let desiredWidth = CGFloat(appCount) * preferredColumnWidth + groupSpacing + controlsWidth
        let width = min(maxWidth, max(isAccessibilityTrustedWidth, desiredWidth))
        let desiredHeight = CGFloat(maxWindowCount) * 35 + CGFloat(max(maxWindowCount - 1, 0)) * 2 + 4
        let height = min(screenFrame.height * 0.58, max(42, desiredHeight))

        let defaultOrigin = NSPoint(x: screenFrame.maxX - width - 4, y: screenFrame.minY + 4)
        let proposedOrigin = customPanelOrigins[.matrix] ?? defaultOrigin
        let maxX = max(screenFrame.minX, screenFrame.maxX - width)
        let maxY = max(screenFrame.minY, screenFrame.maxY - height)
        let origin = NSPoint(
            x: min(max(proposedOrigin.x, screenFrame.minX), maxX),
            y: min(max(proposedOrigin.y, screenFrame.minY), maxY)
        )
        let frame = NSRect(origin: origin, size: NSSize(width: width, height: height))
        setPanelFrameIfNeeded(frame)
    }

    private func setPanelFrameIfNeeded(_ frame: NSRect) {
        guard let panel else { return }
        let current = panel.frame
        let unchanged = abs(current.minX - frame.minX) < 0.5 &&
            abs(current.minY - frame.minY) < 0.5 &&
            abs(current.width - frame.width) < 0.5 &&
            abs(current.height - frame.height) < 0.5
        guard !unchanged else { return }
        panel.setFrame(frame, display: true)
    }

    private var isAccessibilityTrustedWidth: CGFloat {
        permissionService.isTrusted ? 0 : 380
    }

    private func refresh() {
        syncAppFocusObservers()
        let refreshedWindows = windowService.enumerateWindows(
            excludingPID: ProcessInfo.processInfo.processIdentifier,
            showHiddenApps: settings.showHiddenApps,
            blacklistedAppKeys: settings.blacklistedAppKeys
        )
        windows = refreshedWindows
        settings.reconcileAppOrder(with: windows.map(\.appKey))
        reposition()
        updateWindowSpaceReservations()
        let signature = windowRenderSignature(isTrusted: permissionService.isTrusted)
        if signature != lastRenderedWindowSignature {
            lastRenderedWindowSignature = signature
            hostingView?.rootView = TaskbarView(
                windows: windows,
                isAccessibilityTrusted: permissionService.isTrusted,
                onRequestPermission: { [weak self] in self?.requestPermission() },
                onSelect: { [weak self] window in self?.select(window) },
                onMinimizeAll: { [weak self] in self?.minimizeAll() },
                onShowAppWindows: { [weak self] window in self?.showAppWindows(for: window) },
                onClose: { [weak self] window in self?.close(window) },
                settings: settings,
                onSettingsChanged: { [weak self] in self?.refresh() },
                onOpenSettings: { [weak self] in self?.openSettings() },
                onAppDragChanged: { [weak self] isDragging in self?.setAppReordering(isDragging) },
                onPanelDragChanged: { [weak self] translation in self?.movePanel(by: translation) },
                onPanelDragEnded: { [weak self] in self?.finishPanelDrag() },
                onHideTaskbar: { [weak self] in self?.hideInDock() },
                onQuit: { NSApp.terminate(nil) }
            )
        }
        if isHiddenInDock {
            panel?.orderOut(nil)
        } else if panel?.isVisible != true {
            panel?.orderFrontRegardless()
        }
    }

    private func requestPermission() { permissionService.requestAccess(); refresh() }
    private func select(_ window: WindowModel) {
        _ = windowService.toggle(window)
        refreshAfterWindowAction()
    }
    private func minimizeAll() {
        windowService.minimizeAll(windows)
        refreshAfterWindowAction()
    }
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

    private func automaticRefresh() {
        if let pauseUntil = reorderRefreshPauseUntil, pauseUntil > Date() { return }
        reorderRefreshPauseUntil = nil
        refresh()
    }

    private func setAppReordering(_ isDragging: Bool) {
        if isDragging {
            // Keep the SwiftUI root intact while the reorder gesture is active.
            // The deadline also recovers automatically when a drag is cancelled outside TaskDock.
            reorderRefreshPauseUntil = Date().addingTimeInterval(10)
        } else {
            reorderRefreshPauseUntil = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.refresh()
            }
        }
    }

    private func refreshAfterWindowAction() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.refresh()
        }
    }

    private func movePanel(by translation: CGSize) {
        guard !isHiddenInDock, let panel else { return }
        if panelDragStartOrigin == nil { panelDragStartOrigin = panel.frame.origin }
        guard let start = panelDragStartOrigin else { return }

        let screenFrame = (panel.screen ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        let proposedX = start.x + translation.width
        let proposedY = start.y - translation.height
        let maxX = max(screenFrame.minX, screenFrame.maxX - panel.frame.width)
        let maxY = max(screenFrame.minY, screenFrame.maxY - panel.frame.height)
        panel.setFrameOrigin(NSPoint(
            x: min(max(proposedX, screenFrame.minX), maxX),
            y: min(max(proposedY, screenFrame.minY), maxY)
        ))
    }

    private func finishPanelDrag() {
        if panelDragStartOrigin != nil, let panel {
            customPanelOrigins[settings.layoutMode] = panel.frame.origin
        }
        panelDragStartOrigin = nil
        refresh()
    }

    private func hideInDock() {
        isHiddenInDock = true
        dockRestoreAvailableAt = Date().addingTimeInterval(0.8)
        finishPanelDrag()
        settingsWindowController?.hide()
        windowService.clearWindowSpaceReservations(restore: true, windows: windows)
        NSApp.setActivationPolicy(.regular)
        panel?.orderOut(nil)
    }

    private func toggleTaskbarVisibility() {
        if isHiddenInDock {
            dockRestoreAvailableAt = .distantPast
            restoreFromDock()
        } else {
            hideInDock()
        }
    }

    private func windowRenderSignature(isTrusted: Bool) -> String {
        let windowState = windows.map {
            "\($0.id)|\($0.title)|\($0.isMinimized)|\($0.isFocused)|\($0.isMain)"
        }.joined(separator: "\u{1F}")
        return "\(isTrusted)|\(windowState)"
    }

    private func updateWindowSpaceReservations() {
        guard let panel,
              let screen = panel.screen ?? NSScreen.screens.first else { return }
        let reservationWindows = windowService.enumerateWindows(
            excludingPID: ProcessInfo.processInfo.processIdentifier,
            showHiddenApps: true,
            blacklistedAppKeys: []
        )
        windowService.updateWindowSpaceReservations(
            for: reservationWindows,
            panelFrame: panel.frame,
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            enabled: !isHiddenInDock && panel.isVisible
        )
    }

    private func syncAppFocusObservers() {
        guard permissionService.isTrusted else {
            removeAllAppFocusObservers()
            return
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let currentPIDs = Set(NSWorkspace.shared.runningApplications
            .filter { $0.processIdentifier != ownPID && $0.activationPolicy == .regular }
            .map(\.processIdentifier))

        for pid in appFocusObservers.keys where !currentPIDs.contains(pid) {
            removeAppFocusObserver(for: pid)
        }

        for pid in currentPIDs where appFocusObservers[pid] == nil {
            var observer: AXObserver?
            guard AXObserverCreate(pid, Self.focusObserverCallback, &observer) == .success,
                  let observer else { continue }
            let application = AXUIElementCreateApplication(pid)
            let context = Unmanaged.passUnretained(self).toOpaque()
            let notifications = [
                kAXFocusedWindowChangedNotification,
                kAXMainWindowChangedNotification,
                kAXWindowMiniaturizedNotification,
                kAXWindowDeminiaturizedNotification
            ]
            var registered = false
            for notification in notifications {
                if AXObserverAddNotification(observer, application, notification as CFString, context) == .success {
                    registered = true
                }
            }
            guard registered else { continue }
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            appFocusObservers[pid] = AppFocusObserver(observer: observer, application: application)
        }
    }

    private func removeAppFocusObserver(for pid: pid_t) {
        guard let entry = appFocusObservers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(entry.observer), .commonModes)
    }

    private func removeAllAppFocusObservers() {
        for pid in Array(appFocusObservers.keys) {
            removeAppFocusObserver(for: pid)
        }
    }

    @objc private func workspaceChanged(_ notification: Notification) {
        refresh()
        guard notification.name == NSWorkspace.didActivateApplicationNotification else { return }
        // Alt-Tab helpers can publish app activation just before Accessibility updates
        // AXMainWindow. Refresh once more after that short hand-off settles.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.refresh()
        }
    }
}
