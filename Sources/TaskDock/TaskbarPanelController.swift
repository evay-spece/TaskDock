import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class TaskbarPanelController {
    private struct AppFocusObserver {
        let observer: AXObserver
        let application: AXUIElement
    }

    private let permissionService = AccessibilityPermissionService()
    private let windowService = AXWindowService()
    private let dockGeometryService = DockGeometryService()
    private let settings = SettingsStore()
    private var panel: NSPanel?
    private var timer: Timer?
    private var windows: [WindowModel] = []
    private var hostingView: NSHostingView<TaskbarView>?
    private var dockFinderPanel: NSPanel?
    private var dockFinderHostingView: NSHostingView<TaskbarView>?
    private var settingsWindowController: SettingsWindowController?
    private var reorderRefreshPauseUntil: Date?
    private var panelDragStartOrigin: NSPoint?
    private var customPanelOrigins: [TaskDockLayoutMode: NSPoint] = [:]
    private var isHiddenInDock = false
    private var dockRestoreAvailableAt = Date.distantPast
    private var shortcutMonitor: ModifierDoubleTapMonitor?
    private var lastRenderedWindowSignature = ""
    private var appFocusObservers: [pid_t: AppFocusObserver] = [:]
    private var appliedTaskbarAlignment: TaskbarAlignment?
    private var appliedLayoutMode: TaskDockLayoutMode?
    private var favoriteMagnificationExpansion: CGFloat = 0
    private var stableDockGeometry: DockGeometrySnapshot?
    private var pendingDockGeometry: DockGeometrySnapshot?
    private var pendingDockGeometrySince: Date?

    private static let focusObserverCallback: AXObserverCallback = { _, _, _, context in
        guard let context else { return }
        let controller = Unmanaged<TaskbarPanelController>.fromOpaque(context).takeUnretainedValue()
        Task { @MainActor [weak controller] in
            controller?.refresh()
        }
    }

    func show() {
        let view = makeTaskbarView(windows: windows, showsFavorites: true, showsControls: true, showsEmptyState: true)
        let hosting = NSHostingView(rootView: view)
        hostingView = hosting
        let panel = makePanel(contentView: hosting)
        self.panel = panel

        let finderView = makeTaskbarView(windows: [], showsFavorites: false, showsControls: false, showsEmptyState: false)
        let finderHosting = NSHostingView(rootView: finderView)
        dockFinderHostingView = finderHosting
        dockFinderPanel = makePanel(contentView: finderHosting)
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
        dockFinderPanel?.orderOut(nil)
    }

    func restoreFromDock() {
        guard isHiddenInDock, Date() >= dockRestoreAvailableAt else { return }
        isHiddenInDock = false
        NSApp.setActivationPolicy(.accessory)
        refresh()
        panel?.orderFrontRegardless()
        if settings.layoutMode == .dockCompanion, !finderWindows.isEmpty {
            dockFinderPanel?.orderFrontRegardless()
        }
    }

    var currentLayoutMode: TaskDockLayoutMode { settings.layoutMode }
    var isTaskDockHidden: Bool { isHiddenInDock }

    func minimizeAllWindows() {
        minimizeAll()
    }

    func setLayoutMode(_ mode: TaskDockLayoutMode) {
        guard settings.layoutMode != mode else { return }
        favoriteMagnificationExpansion = 0
        settings.layoutMode = mode
        refresh()
    }

    func presentSettings() {
        openSettings()
    }

    func hideTaskDock() {
        hideInDock()
    }

    func showTaskDock() {
        dockRestoreAvailableAt = .distantPast
        restoreFromDock()
    }

    private func makePanel(contentView: NSView) -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.contentView = contentView
        return panel
    }

    private func makeTaskbarView(
        windows: [WindowModel],
        showsFavorites: Bool,
        showsControls: Bool,
        showsEmptyState: Bool
    ) -> TaskbarView {
        TaskbarView(
            windows: windows,
            isAccessibilityTrusted: permissionService.isTrusted,
            onRequestPermission: { [weak self] in self?.requestPermission() },
            onSelect: { [weak self] window in self?.select(window) },
            onMinimizeAll: { [weak self] in self?.minimizeAll() },
            onShowAppWindows: { [weak self] window in self?.showAppWindows(for: window) },
            onClose: { [weak self] window in self?.close(window) },
            onOpenFavorite: { [weak self] favorite in self?.openFavorite(favorite) },
            showsFavorites: showsFavorites,
            showsControls: showsControls,
            showsEmptyState: showsEmptyState,
            settings: settings,
            onSettingsChanged: { [weak self] in self?.refresh() },
            onAppDragChanged: { [weak self] isDragging in self?.setAppReordering(isDragging) },
            onFavoriteMagnificationChanged: { [weak self] expansion in
                self?.setFavoriteMagnificationExpansion(expansion)
            },
            onPanelDragChanged: { [weak self] translation in self?.movePanel(by: translation) },
            onPanelDragEnded: { [weak self] in self?.finishPanelDrag() }
        )
    }

    private func reposition(animated: Bool = false) {
        guard let screen = NSScreen.screens.first, panel != nil else { return }
        let screenFrame = screen.visibleFrame

        if appliedLayoutMode != settings.layoutMode {
            appliedLayoutMode = settings.layoutMode
            if settings.layoutMode == .dockCompanion {
                stableDockGeometry = nil
                pendingDockGeometry = nil
                pendingDockGeometrySince = nil
            }
        }

        if settings.layoutMode == .dockCompanion {
            repositionBesideDock(on: screen)
            return
        }
        dockFinderPanel?.orderOut(nil)

        if settings.layoutMode == .taskbar {
            if appliedTaskbarAlignment != settings.taskbarAlignment {
                customPanelOrigins.removeValue(forKey: .taskbar)
                appliedTaskbarAlignment = settings.taskbarAlignment
            }
            let preferredItemWidth: CGFloat = 198
            let favoriteWidth = settings.favoriteApps.isEmpty
                ? 0
                : CGFloat(settings.favoriteApps.count) * 32 + CGFloat(max(settings.favoriteApps.count - 1, 0)) * 2 + 14 + favoriteMagnificationExpansion
            let controlsAndPadding: CGFloat = 48 + favoriteWidth
            let itemSpacing = CGFloat(max(windows.count - 1, 0)) * 4
            let desiredWidth: CGFloat
            if !permissionService.isTrusted {
                desiredWidth = 600
            } else if windows.isEmpty {
                desiredWidth = max(390, controlsAndPadding + 90)
            } else {
                desiredWidth = CGFloat(windows.count) * preferredItemWidth + itemSpacing + controlsAndPadding
            }
            let width = min(screenFrame.width - 24, desiredWidth)
            // Keep transparent headroom above the 38-point taskbar so favorite
            // icons can magnify upward without changing the taskbar's base height.
            let height: CGFloat = 58
            let defaultX: CGFloat
            switch settings.taskbarAlignment {
            case .left:
                defaultX = screenFrame.minX + 4
            case .center:
                defaultX = screenFrame.midX - width / 2
            case .right:
                defaultX = screenFrame.maxX - width - 4
            }
            let defaultOrigin = NSPoint(x: defaultX, y: screenFrame.minY + 4)
            let proposedOrigin = customPanelOrigins[.taskbar] ?? defaultOrigin
            let maxX = max(screenFrame.minX, screenFrame.maxX - width)
            let maxY = max(screenFrame.minY, screenFrame.maxY - height)
            let origin = NSPoint(
                x: min(max(proposedOrigin.x, screenFrame.minX), maxX),
                y: min(max(proposedOrigin.y, screenFrame.minY), maxY)
            )
            setPanelFrameIfNeeded(
                NSRect(origin: origin, size: NSSize(width: width, height: height)),
                animated: animated
            )
            return
        }

        let appGroups = Dictionary(grouping: windows, by: \.appKey)
        let appCount = max(appGroups.count, 1)
        let maxWindowCount = max(appGroups.values.map(\.count).max() ?? 1, 1)
        let groupSpacing = CGFloat(max(appCount - 1, 0)) * 6
        let controlsWidth: CGFloat = 44
        let preferredColumnWidth: CGFloat = 162
        let maxWidth = screenFrame.width - 24
        let desiredWidth = CGFloat(appCount) * preferredColumnWidth + groupSpacing + controlsWidth
        let width = min(maxWidth, max(isAccessibilityTrustedWidth, desiredWidth))
        let desiredHeight = CGFloat(maxWindowCount) * 32 + CGFloat(max(maxWindowCount - 1, 0)) * 2 + 4
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

    private func repositionBesideDock(on screen: NSScreen) {
        let screenFrame = screen.visibleFrame
        guard let observedDockGeometry = dockGeometryService.bottomDockGeometry(
            on: screen,
            minimizedWindowCount: windows.filter(\.isMinimized).count
        ) else {
            // Accessibility can briefly omit the Dock during login/relaunch.
            // Keep TaskDock usable at the bottom-right until the next refresh.
            let fallbackWidth = min(screenFrame.width - 24, taskbarDesiredWidth(for: otherWindows, showsFavorites: false, showsControls: true))
            let fallbackHeight: CGFloat = 59
            settings.dockCompanionHeight = 39
            setPanelFrameIfNeeded(NSRect(
                x: screenFrame.maxX - fallbackWidth - 4,
                y: screenFrame.minY + 4,
                width: fallbackWidth,
                height: fallbackHeight
            ), animated: shouldAnimateDockPanel(panel))
            dockFinderPanel?.orderOut(nil)
            return
        }
        let dockFrame = stabilizedDockFrame(for: observedDockGeometry)

        let gap: CGFloat = 6
        let edgeInset: CGFloat = 4
        let rightSpace = max(0, screenFrame.maxX - dockFrame.maxX - gap - edgeInset)
        let leftSpace = max(0, dockFrame.minX - screenFrame.minX - gap - edgeInset)
        let baseHeight = min(max(dockFrame.height, 34), 72)
        if abs(settings.dockCompanionHeight - baseHeight) > 0.5 {
            settings.dockCompanionHeight = baseHeight
        }

        let rightDesiredWidth = taskbarDesiredWidth(for: otherWindows, showsFavorites: false, showsControls: true)
        let rightWidth = min(rightDesiredWidth, max(180, rightSpace))
        setPanelFrameIfNeeded(NSRect(
            x: min(dockFrame.maxX + gap, screenFrame.maxX - rightWidth - edgeInset),
            y: dockFrame.minY,
            width: rightWidth,
            height: baseHeight + 20
        ), animated: shouldAnimateDockPanel(panel), animationDuration: 0.2)

        if finderWindows.isEmpty || leftSpace < 80 {
            dockFinderPanel?.orderOut(nil)
        } else {
            let leftDesiredWidth = taskbarDesiredWidth(for: finderWindows, showsFavorites: false, showsControls: false)
            let leftWidth = min(leftDesiredWidth, leftSpace)
            setPanelFrameIfNeeded(
                NSRect(
                    x: dockFrame.minX - gap - leftWidth,
                    y: dockFrame.minY,
                    width: leftWidth,
                    height: baseHeight + 20
                ),
                panel: dockFinderPanel,
                animated: shouldAnimateDockPanel(dockFinderPanel),
                animationDuration: 0.2
            )
        }
    }

    private func taskbarDesiredWidth(
        for displayedWindows: [WindowModel],
        showsFavorites: Bool,
        showsControls: Bool
    ) -> CGFloat {
        let preferredItemWidth: CGFloat = 174
        let favoriteWidth = !showsFavorites || settings.favoriteApps.isEmpty
            ? 0
            : CGFloat(settings.favoriteApps.count) * 32 + CGFloat(max(settings.favoriteApps.count - 1, 0)) * 2 + 14
        let controlsAndPadding: CGFloat = (showsControls ? 48 : 16) + favoriteWidth
        let itemSpacing = CGFloat(max(displayedWindows.count - 1, 0)) * 4
        if !permissionService.isTrusted { return 600 }
        if displayedWindows.isEmpty { return showsControls ? controlsAndPadding : 0 }
        return CGFloat(displayedWindows.count) * preferredItemWidth + itemSpacing + controlsAndPadding
    }

    private func stabilizedDockFrame(for observed: DockGeometrySnapshot) -> CGRect {
        if stableDockGeometry == nil {
            if !observed.isMagnified {
                stableDockGeometry = observed
            }
            return observed.frame
        }
        guard let stableDockGeometry else { return observed.frame }

        if observed.isMagnified {
            return stableDockGeometry.frame
        }
        if observed.layoutSignature == stableDockGeometry.layoutSignature {
            pendingDockGeometry = nil
            pendingDockGeometrySince = nil
            return stableDockGeometry.frame
        }

        if pendingDockGeometry?.layoutSignature != observed.layoutSignature {
            pendingDockGeometry = observed
            pendingDockGeometrySince = Date()
            return stableDockGeometry.frame
        }
        pendingDockGeometry = observed
        guard let pendingDockGeometrySince,
              Date().timeIntervalSince(pendingDockGeometrySince) >= 1.5 else {
            return stableDockGeometry.frame
        }

        self.stableDockGeometry = observed
        pendingDockGeometry = nil
        self.pendingDockGeometrySince = nil
        return observed.frame
    }

    private func setPanelFrameIfNeeded(
        _ frame: NSRect,
        panel targetPanel: NSPanel? = nil,
        animated: Bool = false,
        animationDuration: TimeInterval = 0.16
    ) {
        guard let panel = targetPanel ?? panel else { return }
        let current = panel.frame
        let unchanged = abs(current.minX - frame.minX) < 0.5 &&
            abs(current.minY - frame.minY) < 0.5 &&
            abs(current.width - frame.width) < 0.5 &&
            abs(current.height - frame.height) < 0.5
        guard !unchanged else { return }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = animationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                context.allowsImplicitAnimation = true
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    private func shouldAnimateDockPanel(_ panel: NSPanel?) -> Bool {
        guard let panel else { return false }
        return panel.isVisible && panel.frame.width > 4 && panel.frame.height > 4
    }

    private var dockCompanionWindows: [WindowModel] {
        let countsByApp = Dictionary(grouping: windows, by: \.appKey).mapValues(\.count)
        return windows.filter {
            $0.bundleIdentifier == "com.apple.finder" || countsByApp[$0.appKey, default: 0] >= 2
        }
    }

    private var finderWindows: [WindowModel] {
        dockCompanionWindows.filter { $0.bundleIdentifier == "com.apple.finder" }
    }

    private var otherWindows: [WindowModel] {
        dockCompanionWindows.filter { $0.bundleIdentifier != "com.apple.finder" }
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
            let primaryWindows = settings.layoutMode == .dockCompanion ? otherWindows : windows
            hostingView?.rootView = makeTaskbarView(
                windows: primaryWindows,
                showsFavorites: settings.layoutMode != .dockCompanion,
                showsControls: true,
                showsEmptyState: settings.layoutMode != .dockCompanion
            )
            dockFinderHostingView?.rootView = makeTaskbarView(
                windows: finderWindows,
                showsFavorites: false,
                showsControls: false,
                showsEmptyState: false
            )
        }
        if isHiddenInDock {
            panel?.orderOut(nil)
            dockFinderPanel?.orderOut(nil)
        } else if panel?.isVisible != true {
            panel?.orderFrontRegardless()
        }
        if !isHiddenInDock, settings.layoutMode == .dockCompanion, !finderWindows.isEmpty {
            if dockFinderPanel?.isVisible != true { dockFinderPanel?.orderFrontRegardless() }
        } else {
            dockFinderPanel?.orderOut(nil)
        }
    }

    private func requestPermission() { permissionService.requestAccess(); refresh() }
    private func select(_ window: WindowModel) {
        _ = windowService.toggle(window)
        refreshAfterWindowAction()
    }
    private func minimizeAll() {
        let allWindows = windowService.enumerateWindows(
            excludingPID: ProcessInfo.processInfo.processIdentifier,
            showHiddenApps: true,
            blacklistedAppKeys: []
        )
        windowService.minimizeAll(allWindows)
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
    private func openFavorite(_ favorite: FavoriteApp) {
        let runningApp = NSWorkspace.shared.runningApplications.first { app in
            if let bundleIdentifier = favorite.bundleIdentifier,
               app.bundleIdentifier == bundleIdentifier { return true }
            guard let bundlePath = favorite.bundlePath else { return false }
            return app.bundleURL?.path == bundlePath
        }
        if let runningApp {
            _ = windowService.reopenApplication(runningApp)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self, weak runningApp] in
                guard let self, let runningApp else { return }
                _ = self.windowService.activateApplication(runningApp)
            }
            return
        }

        let applicationURL = favorite.bundleIdentifier.flatMap {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
        } ?? favorite.bundlePath.map(URL.init(fileURLWithPath:))
        guard let applicationURL else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(
            at: applicationURL,
            configuration: configuration
        )
    }
    private func openSettings() {
        let configurableWindows = windowService.enumerateWindows(
            excludingPID: ProcessInfo.processInfo.processIdentifier,
            showHiddenApps: true,
            blacklistedAppKeys: []
        )
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(settings: settings, windows: configurableWindows) { [weak self] in
                self?.refresh()
            }
        }
        settingsWindowController?.update(windows: configurableWindows)
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

    private func setFavoriteMagnificationExpansion(_ expansion: CGFloat) {
        let resolvedExpansion = settings.layoutMode == .taskbar ? expansion : 0
        guard abs(favoriteMagnificationExpansion - resolvedExpansion) >= 0.5 else { return }
        favoriteMagnificationExpansion = resolvedExpansion
        reposition(animated: true)
    }

    private func refreshAfterWindowAction() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.refresh()
        }
    }

    private func movePanel(by translation: CGSize) {
        guard !isHiddenInDock, settings.layoutMode != .dockCompanion, let panel else { return }
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
        dockFinderPanel?.orderOut(nil)
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
        return "\(isTrusted)|\(settings.layoutMode.rawValue)|\(windowState)"
    }

    private func updateWindowSpaceReservations() {
        guard let panel,
              let screen = panel.screen ?? NSScreen.screens.first else { return }
        let reservationWindows = windowService.enumerateWindows(
            excludingPID: ProcessInfo.processInfo.processIdentifier,
            showHiddenApps: true,
            blacklistedAppKeys: []
        )
        let reservationPanelFrame: CGRect
        if settings.layoutMode == .dockCompanion,
           let finderPanel = dockFinderPanel,
           finderPanel.isVisible {
            let minX = min(panel.frame.minX, finderPanel.frame.minX)
            let maxX = max(panel.frame.maxX, finderPanel.frame.maxX)
            reservationPanelFrame = CGRect(
                x: minX,
                y: min(panel.frame.minY, finderPanel.frame.minY),
                width: maxX - minX,
                height: settings.dockCompanionHeight
            )
        } else if settings.layoutMode == .taskbar || settings.layoutMode == .dockCompanion {
            reservationPanelFrame = CGRect(
                x: panel.frame.minX,
                y: panel.frame.minY,
                width: panel.frame.width,
                height: settings.layoutMode == .dockCompanion ? settings.dockCompanionHeight : 38
            )
        } else {
            reservationPanelFrame = panel.frame
        }
        windowService.updateWindowSpaceReservations(
            for: reservationWindows,
            panelFrame: reservationPanelFrame,
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
