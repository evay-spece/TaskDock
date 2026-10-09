import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class TaskbarPanelController {
    private struct ReservationContext: Equatable {
        let panelFrame: CGRect
        let screenFrame: CGRect
        let visibleFrame: CGRect
        let enabled: Bool
        let layoutMode: TaskDockLayoutMode
    }

    private struct AppFocusObserver {
        let observer: AXObserver
        let application: AXUIElement
    }

    private let permissionService = AccessibilityPermissionService()
    private let windowService = AXWindowService()
    private let dockGeometryService = DockGeometryService()
    private let settings = SettingsStore()
    private let systemDockVisibility = SystemDockVisibilityController()
    private let trashStatus = TrashStatusService()
    private let favoriteBadges = FavoriteBadgeStore()
    private let trialManager = TrialManager()
    private let badgePollQueue = DispatchQueue(label: "taskdock.dock-badges", qos: .utility)
    private var panel: NSPanel?
    private var timer: Timer?
    private var windows: [WindowModel] = []
    private var bulkMinimizedWindows: [WindowModel] = []
    private var recentApplications: [FavoriteApp] = []
    private let recentAppPopoverState = RecentAppPopoverState()
    private var runningApplicationIDs: Set<String> = []
    private var recentWindowFocusDates: [String: Date] = [:]
    private var hostingView: NSHostingView<TaskbarView>?
    private var dockFinderPanel: NSPanel?
    private var dockFinderHostingView: NSHostingView<TaskbarView>?
    private var settingsWindowController: SettingsWindowController?
    private var reorderRefreshPauseUntil: Date?
    private var favoriteHoverActiveUntil: Date?
    private var favoriteHoverRefreshPauseUntil: Date?
    private var settingsRefreshPauseUntil: Date?
    private var pendingLayoutRefreshToken: UUID?
    private var lastReservationContext: ReservationContext?
    private var lastReservationUpdateAt = Date.distantPast
    private var isHiddenInDock = false
    private var dockRestoreAvailableAt = Date.distantPast
    private var shortcutMonitor: ModifierDoubleTapMonitor?
    private var minimizeHotKeyMonitor: GlobalMinimizeHotKeyMonitor?
    private var optionHotKeyMonitor: OptionWindowHotKeyMonitor?
    private var registeredOptionShortcuts = OptionWindowHotKeyMonitor.Registered()
    private var registeredWindowCount = -1
    private var registeredFavoriteCount = -1
    private var registeredShortcutMode: TaskDockLayoutMode?
    private var lastRenderedWindowSignature = ""
    private var lastBadgePollAt = Date.distantPast
    private var badgePollInFlight = false
    private var appFocusObservers: [pid_t: AppFocusObserver] = [:]
    private var appliedLayoutMode: TaskDockLayoutMode?
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
        synchronizeSystemDockVisibility()
        seedRecentApplications()
        let view = makeTaskbarView(windows: windows, showsFavorites: true, showsControls: true, showsEmptyState: true)
        let hosting = NSHostingView(rootView: view)
        hostingView = hosting
        let panel = makePanel(contentView: hosting)
        self.panel = panel

        let finderView = makeTaskbarView(windows: [], showsFavorites: false, showsControls: false, showsEmptyState: false)
        let finderHosting = NSHostingView(rootView: finderView)
        dockFinderHostingView = finderHosting
        dockFinderPanel = makePanel(contentView: finderHosting)
        optionHotKeyMonitor = OptionWindowHotKeyMonitor { [weak self] target in
            switch target {
            case .window(let index): self?.openShortcutWindow(index)
            case .favorite(let index): self?.openShortcutFavorite(index)
            }
        }
        minimizeHotKeyMonitor = GlobalMinimizeHotKeyMonitor { [weak self] in
            self?.recordTrialOperation()
            self?.minimizeAll()
        }
        minimizeHotKeyMonitor?.start()
        shortcutMonitor = ModifierDoubleTapMonitor(
            settings: settings,
            onDoubleTap: { [weak self] in self?.toggleTaskbarVisibility() },
            onOptionHoldChanged: { [weak self] isHeld in self?.setOptionShortcutsVisible(isHeld) }
        )
        shortcutMonitor?.start()
        reposition()
        panel.orderFrontRegardless()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
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
        bulkMinimizedWindows = []
        minimizeHotKeyMonitor?.stop()
        minimizeHotKeyMonitor = nil
        systemDockVisibility.restore()
        pendingLayoutRefreshToken = nil
        timer?.invalidate()
        shortcutMonitor?.stop()
        stopRegisteredHotKeys()
        settings.activeTaskbarShortcutIndices = []
        settings.activeFavoriteShortcutIndices = []
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
    var canRestoreMinimizedWindows: Bool {
        !bulkMinimizedWindows.isEmpty &&
            bulkMinimizedWindows.contains { windowService.isMinimized($0) } &&
            !hasVisibleWindowOutsideTaskDock()
    }

    func minimizeAllWindows() {
        minimizeAll()
    }

    func setLayoutMode(_ mode: TaskDockLayoutMode) {
        guard settings.layoutMode != mode else { return }
        setOptionShortcutsVisible(false)
        stopRegisteredHotKeys()
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
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.acceptsMouseMovedEvents = true
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
            recentApplications: settings.layoutMode == .taskbar ? recentApplications : [],
            recentAppPopoverState: recentAppPopoverState,
            runningApplicationIDs: settings.layoutMode == .taskbar ? runningApplicationIDs : [],
            favoriteBadges: favoriteBadges,
            isAccessibilityTrusted: permissionService.isTrusted,
            canRestoreMinimizedWindows: !bulkMinimizedWindows.isEmpty,
            onRequestPermission: { [weak self] in self?.requestPermission() },
            onSelect: { [weak self] window in self?.recordTrialOperation(); self?.select(window) },
            onMinimizeAll: { [weak self] in self?.recordTrialOperation(); self?.minimizeAll() },
            onOpenTrash: { [weak self] in self?.recordTrialOperation(); self?.openTrash() },
            onEmptyTrash: { [weak self] in self?.recordTrialOperation(); self?.emptyTrash() },
            onRestoreLatestTrashItem: { [weak self] in self?.recordTrialOperation(); self?.restoreLatestTrashItem() },
            onOpenFolder: { [weak self] folder in
                self?.recordTrialOperation()
                NSWorkspace.shared.open(folder.url)
            },
            onShowAppWindows: { [weak self] window in self?.recordTrialOperation(); self?.showAppWindows(for: window) },
            onBlockWindowType: { [weak self] window in self?.recordTrialOperation(); self?.blockWindowType(window) },
            onClose: { [weak self] window in self?.recordTrialOperation(); self?.close(window) },
            onOpenFavorite: { [weak self] favorite in self?.recordTrialOperation(); self?.openFavorite(favorite) },
            onPerformWindowAction: { action in action() },
            onQuitRecentApp: { [weak self] favorite in self?.recordTrialOperation(); self?.quitRecentApp(favorite) },
            showsFavorites: showsFavorites,
            showsControls: showsControls,
            showsEmptyState: showsEmptyState,
            settings: settings,
            trashStatus: trashStatus,
            onSettingsChanged: { [weak self] in
                self?.lastRenderedWindowSignature = ""
                self?.refresh()
            },
            onRecentPopoverVisibilityChanged: { [weak self] isOpen in
                guard let self else { return }
                if !isOpen { self.refresh() }
            },
            onAppDragChanged: { [weak self] isDragging in self?.setAppReordering(isDragging) },
            onFavoriteHoverActivity: { [weak self] isActive in self?.setFavoriteHoverActivity(isActive) }
        )
    }

    private func recordTrialOperation() {
        guard trialManager.recordOperation() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.trialManager.isExpired() else { return }
            let alert = NSAlert()
            alert.messageText = "TaskDock 试用期已结束"
            alert.informativeText = "你仍可继续使用。此提醒会在每 10 次任务栏操作后再次出现。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "稍后")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    private func reposition(
        animated: Bool = false,
        animationDuration: TimeInterval = 0.16,
        animationTimingFunction: CAMediaTimingFunction? = nil
    ) {
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
        panel?.level = .floating
        dockFinderPanel?.level = .floating

        let scale = settings.taskbarHeight / SettingsStore.defaultTaskbarHeight
        // Keep the transparent side margins inside the window so magnified
        // icons can draw and receive pointer events beyond the idle bar.
        let height = settings.taskbarHeight + FavoriteMagnificationLayout.headroom(
            for: scale, peakScale: settings.favoriteMagnificationScale)
        let physicalBottom = screen.frame.minY
        let origin = NSPoint(x: screenFrame.minX, y: physicalBottom)
        setPanelFrameIfNeeded(
            NSRect(origin: origin, size: NSSize(width: screenFrame.width, height: height)),
            animated: animated,
            animationDuration: animationDuration,
            animationTimingFunction: animationTimingFunction
        )
    }

    private func repositionBesideDock(on screen: NSScreen) {
        let screenFrame = screen.visibleFrame
        if !settings.dockCompanionOverlayEnabled {
            panel?.level = .floating
            dockFinderPanel?.level = .floating
        }
        guard let observedDockGeometry = dockGeometryService.bottomDockGeometry(
            on: screen,
            minimizedWindowCount: windows.filter(\.isMinimized).count
        ) else {
            // Accessibility can briefly omit the Dock during login/relaunch.
            // Keep TaskDock usable at the bottom-right until the next refresh.
            if !settings.dockCompanionShowsBottomBar && otherWindows.isEmpty {
                panel?.orderOut(nil)
                dockFinderPanel?.orderOut(nil)
                return
            }
            let fallbackWidth = min(screenFrame.width - 24, taskbarDesiredWidth(for: otherWindows, showsFavorites: false, showsControls: true))
            let fallbackDockHeight = DockCompanionSizing.baselineDockHeight
            let fallbackHeight = DockCompanionSizing.panelHeight(for: fallbackDockHeight)
            settings.dockCompanionHeight = fallbackDockHeight
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

        let overlayEnabled = settings.dockCompanionOverlayEnabled && dockFrame.width >= 360
        let dockPanelLevel: NSWindow.Level = overlayEnabled ? .statusBar : .floating
        panel?.level = dockPanelLevel
        dockFinderPanel?.level = dockPanelLevel

        let gap: CGFloat = 2
        let edgeInset: CGFloat = 4
        let rightSpace = max(0, screenFrame.maxX - dockFrame.maxX - gap - edgeInset)
        let leftSpace = max(0, dockFrame.minX - screenFrame.minX - gap - edgeInset)
        let baseHeight = min(max(dockFrame.height, 34), 96)
        if abs(settings.dockCompanionHeight - baseHeight) > 0.5 {
            settings.dockCompanionHeight = baseHeight
        }

        let rightDesiredWidth = taskbarDesiredWidth(for: otherWindows, showsFavorites: false, showsControls: true)
        let hasBottomBar = settings.dockCompanionShowsBottomBar
        let shouldShowRightPanel = hasBottomBar || !otherWindows.isEmpty
        let leftDesiredWidth = taskbarDesiredWidth(for: finderWindows, showsFavorites: false, showsControls: false)
        let shouldShowLeftPanel = !finderWindows.isEmpty && (!overlayEnabled ? leftSpace >= 80 : true)
        let overlayHasBothSides = shouldShowLeftPanel && shouldShowRightPanel
        let overlayMaximumWidth = dockFrame.width * (overlayHasBothSides ? 0.46 : 0.78)
        var rightWidth = hasBottomBar
            ? min(rightDesiredWidth, max(180, rightSpace))
            : min(rightDesiredWidth, rightSpace)
        var leftWidth = shouldShowLeftPanel ? min(leftDesiredWidth, leftSpace) : 0
        if overlayEnabled {
            let availableDockWidth = max(0, dockFrame.width - 12)
            rightWidth = shouldShowRightPanel ? min(rightDesiredWidth, overlayMaximumWidth) : 0
            leftWidth = shouldShowLeftPanel ? min(leftDesiredWidth, overlayMaximumWidth) : 0
            let combinedWidth = rightWidth + leftWidth
            if combinedWidth > availableDockWidth, combinedWidth > 0 {
                let fitScale = availableDockWidth / combinedWidth
                rightWidth *= fitScale
                leftWidth *= fitScale
            }
        }
        if shouldShowRightPanel {
            setPanelFrameIfNeeded(NSRect(
                x: overlayEnabled
                    ? dockFrame.maxX - rightWidth - edgeInset
                    : min(dockFrame.maxX + gap, screenFrame.maxX - rightWidth - edgeInset),
                y: dockFrame.minY,
                width: rightWidth,
                height: DockCompanionSizing.panelHeight(for: baseHeight)
            ), animated: shouldAnimateDockPanel(panel), animationDuration: 0.2)
        } else {
            panel?.orderOut(nil)
        }

        if !shouldShowLeftPanel || leftWidth < 1 {
            dockFinderPanel?.orderOut(nil)
        } else {
            setPanelFrameIfNeeded(
                NSRect(
                    x: overlayEnabled
                        ? dockFrame.minX + edgeInset
                        : dockFrame.minX - gap - leftWidth,
                    y: dockFrame.minY,
                    width: leftWidth,
                    height: DockCompanionSizing.panelHeight(for: baseHeight)
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
        let isDockCompanion = settings.layoutMode == .dockCompanion
        let dockHeight = isDockCompanion
            ? settings.dockCompanionHeight
            : DockCompanionSizing.baselineDockHeight
        let panelScale = isDockCompanion ? DockCompanionSizing.scale(for: dockHeight) : 1
        let preferredItemWidth = isDockCompanion
            ? DockCompanionSizing.preferredItemWidth(for: dockHeight)
            : 174
        let favoriteWidth = !showsFavorites || settings.favoriteApps.isEmpty
            ? 0
            : isDockCompanion
                ? CGFloat(settings.favoriteApps.count) * 32
                    + CGFloat(max(settings.favoriteApps.count - 1, 0)) * 2 + 14
                : TaskbarFavoriteLaneLayout.flowWidth(
                    contentWidth: TaskbarFavoriteLaneLayout.contentWidth(
                        appCount: settings.favoriteApps.count,
                        folderCount: settings.favoriteFolders.count),
                    limit: settings.taskbarFavoriteFlowWidth)
        let recentApplicationWidth: CGFloat = !showsFavorites || isDockCompanion || recentApplications.isEmpty
            ? 0 : 40
        let resolvedShowsControls = showsControls && (!isDockCompanion || settings.dockCompanionShowsBottomBar)
        let controlsAndPadding: CGFloat
        if isDockCompanion {
            if showsControls {
                controlsAndPadding = (settings.dockCompanionShowsBottomBar ? 48 : 8) * panelScale
            } else {
                controlsAndPadding = 0
            }
        } else {
            controlsAndPadding = (resolvedShowsControls ? 48 : 16) * panelScale
                + favoriteWidth + recentApplicationWidth
        }
        let spacing = isDockCompanion ? DockCompanionSizing.itemSpacing(for: dockHeight) : 4
        let displayCount = isDockCompanion
            ? FusionDisplayPolicy.displayCount(
                appKeys: displayedWindows.map(\.appKey),
                collapseThreshold: settings.dockCompanionCollapseThreshold
            )
            : settings.taskbarCollapseSameAppWindows
                ? FusionDisplayPolicy.displayCount(
                    appKeys: displayedWindows.map(\.appKey), collapseThreshold: 3)
                : displayedWindows.count
        let itemSpacing = CGFloat(max(displayCount - 1, 0)) * spacing
        if !permissionService.isTrusted { return 600 }
        if displayCount == 0 { return resolvedShowsControls ? controlsAndPadding : 0 }
        return CGFloat(displayCount) * preferredItemWidth + itemSpacing + controlsAndPadding
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
        animationDuration: TimeInterval = 0.16,
        animationTimingFunction: CAMediaTimingFunction? = nil
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
                context.timingFunction = animationTimingFunction ?? CAMediaTimingFunction(name: .easeOut)
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
        let availableAppKeys = Set(countsByApp.keys)
        let recentIDs: Set<String>
        if settings.dockCompanionShowsRecentWindows {
            let candidates = windows.map { window in
                FusionDisplayPolicy.Candidate(
                    id: window.id,
                    appKey: window.appKey,
                    isFocused: window.isFocused,
                    isAllowedOnRight: settings.dockCompanionSide(
                        for: window.appKey, availableAppKeys: availableAppKeys
                    ) == .right
                )
            }
            recentIDs = FusionDisplayPolicy.recentWindowIDs(
                from: candidates,
                focusedAt: recentWindowFocusDates,
                minimumWindowCount: settings.dockCompanionMinimumWindowCount,
                now: Date()
            )
        } else {
            recentIDs = []
        }
        return windows.filter {
            let isFinder = $0.bundleIdentifier == "com.apple.finder"
            guard isFinder || countsByApp[$0.appKey, default: 0] >= settings.dockCompanionMinimumWindowCount
                    || recentIDs.contains($0.id) else {
                return false
            }
            return settings.dockCompanionSide(
                for: $0.appKey,
                availableAppKeys: availableAppKeys
            ) != .hidden
        }
    }

    private var finderWindows: [WindowModel] {
        let availableAppKeys = Set(windows.map(\.appKey))
        return dockCompanionWindows.filter {
            settings.dockCompanionSide(for: $0.appKey, availableAppKeys: availableAppKeys) == .left
        }
    }

    private var otherWindows: [WindowModel] {
        let availableAppKeys = Set(windows.map(\.appKey))
        return dockCompanionWindows.filter {
            settings.dockCompanionSide(for: $0.appKey, availableAppKeys: availableAppKeys) == .right
        }
    }

    private func refresh() {
        if recentAppPopoverState.isPresented { return }
        if isHiddenInDock { setOptionShortcutsVisible(false) }
        // Focus notifications can arrive during a drag even while the timer is paused.
        // Do not enumerate windows or resize the panel until the gesture has settled.
        if let pauseUntil = reorderRefreshPauseUntil, pauseUntil > Date() { return }
        synchronizeSystemDockVisibility()
        syncAppFocusObservers()
        let refreshedWindows = windowService.enumerateWindows(
            excludingPID: ProcessInfo.processInfo.processIdentifier,
            showHiddenApps: settings.showHiddenApps,
            blacklistedAppKeys: settings.blacklistedAppKeys,
            blockedWindowRules: settings.blockedWindowRules,
            finderTabsAsWindows: settings.finderTabsAsWindows
        )
        windows = refreshedWindows
        synchronizeBulkMinimizeState()
        updateRecentWindowFocus()
        refreshRecentApplications()
        refreshFavoriteBadgesIfNeeded()
        if settings.layoutMode == .taskbar { trashStatus.refresh() }
        if settings.layoutMode == .taskbar {
            settings.reconcileTaskbarOrder(with: windows)
        } else {
            settings.reconcileAppOrder(with: windows.map(\.appKey))
        }
        synchronizeHotKeys()
        reposition()
        let signature = windowRenderSignature(isTrusted: permissionService.isTrusted)
        let contentChanged = signature != lastRenderedWindowSignature
        updateWindowSpaceReservations(force: contentChanged)
        if contentChanged {
            lastRenderedWindowSignature = signature
            redrawPanels()
        }
        if isHiddenInDock {
            panel?.orderOut(nil)
            dockFinderPanel?.orderOut(nil)
        } else if settings.layoutMode != .dockCompanion || settings.dockCompanionShowsBottomBar || !otherWindows.isEmpty {
            if panel?.isVisible != true {
                panel?.orderFrontRegardless()
            }
        } else {
            panel?.orderOut(nil)
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

    private func setOptionShortcutsVisible(_ visible: Bool) {
        let shouldShow = visible && !isHiddenInDock && permissionService.isTrusted
        let windowIndices = shouldShow ? registeredOptionShortcuts.windows : []
        let favoriteIndices = shouldShow ? registeredOptionShortcuts.favorites : []
        if settings.activeTaskbarShortcutIndices != windowIndices {
            settings.activeTaskbarShortcutIndices = windowIndices
        }
        if settings.activeFavoriteShortcutIndices != favoriteIndices {
            settings.activeFavoriteShortcutIndices = favoriteIndices
        }
    }

    private func synchronizeHotKeys() {
        guard !isHiddenInDock,
              permissionService.isTrusted else {
            stopRegisteredHotKeys()
            setOptionShortcutsVisible(false)
            return
        }
        let isCompanion = settings.layoutMode == .dockCompanion
        let windowCount = min(
            isCompanion ? fusionShortcutWindows(for: otherWindows).count : windows.count,
            isCompanion ? 5 : OptionWindowHotKeyMonitor.windowShortcutLabels.count
        )
        let favoriteCount = min(
            isCompanion ? fusionShortcutWindows(for: finderWindows).count : settings.favoriteApps.count,
            isCompanion ? 8 : OptionWindowHotKeyMonitor.favoriteShortcutLabels.count
        )
        guard windowCount != registeredWindowCount
                || favoriteCount != registeredFavoriteCount
                || settings.layoutMode != registeredShortcutMode else { return }
        registeredOptionShortcuts = optionHotKeyMonitor?.start(
            windowCount: windowCount,
            favoriteCount: favoriteCount
        ) ?? .init()
        registeredWindowCount = windowCount
        registeredFavoriteCount = favoriteCount
        registeredShortcutMode = settings.layoutMode
        if shortcutMonitor?.isOptionShortcutActive == true {
            setOptionShortcutsVisible(true)
        }
    }

    private func stopRegisteredHotKeys() {
        optionHotKeyMonitor?.stop()
        registeredOptionShortcuts = .init()
        registeredWindowCount = -1
        registeredFavoriteCount = -1
        registeredShortcutMode = nil
    }

    private func openShortcutWindow(_ index: Int) {
        guard !isHiddenInDock,
              registeredOptionShortcuts.windows.contains(index) else { return }
        let ordered = settings.layoutMode == .dockCompanion
            ? fusionShortcutWindows(for: otherWindows)
            : settings.orderedWindows(windows)
        guard ordered.indices.contains(index - 1) else { return }
        _ = windowService.toggle(ordered[index - 1])
        refreshAfterWindowAction()
    }

    private func openShortcutFavorite(_ index: Int) {
        guard !isHiddenInDock,
              registeredOptionShortcuts.favorites.contains(index),
              index > 0 else { return }
        if settings.layoutMode == .dockCompanion {
            let ordered = fusionShortcutWindows(for: finderWindows)
            guard ordered.indices.contains(index - 1) else { return }
            _ = windowService.toggle(ordered[index - 1])
            refreshAfterWindowAction()
            return
        }
        guard settings.favoriteApps.indices.contains(index - 1) else { return }
        let favorite = settings.favoriteApps[index - 1]
        let focusedWindow = windows.first { window in
            windowService.isCurrentlyFocused(window) && (
                favorite.bundleIdentifier.map { $0 == window.bundleIdentifier } ?? false ||
                favorite.bundleIdentifier == nil && window.applicationName == favorite.applicationName
            )
        }
        if let focusedWindow {
            _ = windowService.toggle(focusedWindow)
            refreshAfterWindowAction()
        } else {
            openFavorite(favorite)
        }
    }
    private func minimizeAll() {
        synchronizeBulkMinimizeState()
        if !bulkMinimizedWindows.isEmpty {
            windowService.restoreMinimized(bulkMinimizedWindows)
            bulkMinimizedWindows = []
            refreshAfterWindowAction()
            return
        }
        let allWindows = windowService.enumerateWindows(
            excludingPID: ProcessInfo.processInfo.processIdentifier,
            showHiddenApps: true,
            blacklistedAppKeys: [],
            blockedWindowRules: []
        )
        bulkMinimizedWindows = windowService.minimizeAll(allWindows)
        refreshAfterWindowAction()
    }

    private func synchronizeBulkMinimizeState() {
        guard !bulkMinimizedWindows.isEmpty else { return }
        bulkMinimizedWindows = bulkMinimizedWindows.filter { windowService.isMinimized($0) }
        if hasVisibleWindowOutsideTaskDock() {
            // Opening or restoring any window ends the show-desktop state.
            bulkMinimizedWindows = []
        }
    }

    private func hasVisibleWindowOutsideTaskDock() -> Bool {
        windowService.enumerateWindows(
            excludingPID: ProcessInfo.processInfo.processIdentifier,
            showHiddenApps: false,
            blacklistedAppKeys: [],
            blockedWindowRules: []
        ).contains { !$0.isMinimized }
    }

    private func openTrash() {
        let trashURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".Trash", isDirectory: true)
        NSWorkspace.shared.open(trashURL)
    }

    private func emptyTrash() {
        guard trashStatus.isFull else { return }
        let alert = NSAlert()
        alert.messageText = "清空废纸篓？"
        alert.informativeText = "清空后，废纸篓中的文件将无法从这里恢复。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "清空废纸篓")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        TrashActions.empty { [weak self] error in
            if let error { self?.showTrashActionError(error) }
            self?.trashStatus.refresh(force: true)
        }
    }

    private func restoreLatestTrashItem() {
        TrashActions.restoreLatest { [weak self] error in
            if let error { self?.showTrashActionError(error) }
            self?.trashStatus.refresh(force: true)
        }
    }

    private func showTrashActionError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "废纸篓操作未完成"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        let needsFullDiskAccess = (error as NSError).domain == "TaskDock.Trash"
            && (error as NSError).code == 1
        if needsFullDiskAccess { alert.addButton(withTitle: "打开完全磁盘访问设置") }
        alert.addButton(withTitle: needsFullDiskAccess ? "稍后" : "好")
        let result = alert.runModal()
        if needsFullDiskAccess, result == .alertFirstButtonReturn,
           let settingsURL = URL(string:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(settingsURL)
        }
    }
    private func showAppWindows(for window: WindowModel) {
        windowService.showAllWindows(for: window.pid, from: windows)
        refresh()
    }
    private func blockWindowType(_ window: WindowModel) {
        settings.blockWindowType(for: window)
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
            blacklistedAppKeys: [],
            blockedWindowRules: []
        )
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                settings: settings,
                windows: configurableWindows,
                onChanged: { [weak self] in
                    guard let self else { return }
                    self.pendingLayoutRefreshToken = nil
                    self.settingsRefreshPauseUntil = nil
                    if self.shortcutMonitor?.isOptionShortcutActive == true {
                        self.setOptionShortcutsVisible(true)
                    }
                    self.lastRenderedWindowSignature = ""
                    self.refresh()
                },
                onVisualChanged: { [weak self] in self?.refreshVisualSettings() },
                onLayoutChanged: { [weak self] in self?.refreshLayoutSettings() }
            )
        }
        settingsWindowController?.update(windows: configurableWindows)
        settingsWindowController?.show()
    }

    private func automaticRefresh() {
        if recentAppPopoverState.isPresented { return }
        let now = Date()
        if let pauseUntil = settingsRefreshPauseUntil, pauseUntil > now { return }
        if let pauseUntil = reorderRefreshPauseUntil, pauseUntil > now { return }
        if settings.layoutMode == .taskbar,
           settings.favoriteMagnificationEnabled {
            if let activeUntil = favoriteHoverActiveUntil, activeUntil > now { return }
            if let pauseUntil = favoriteHoverRefreshPauseUntil, pauseUntil > now { return }
        }
        reorderRefreshPauseUntil = nil
        favoriteHoverActiveUntil = nil
        favoriteHoverRefreshPauseUntil = nil
        refresh()
    }

    private func redrawPanels() {
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

    private func refreshVisualSettings() {
        settingsRefreshPauseUntil = Date().addingTimeInterval(0.4)
        redrawPanels()
    }

    private func refreshLayoutSettings() {
        settingsRefreshPauseUntil = Date().addingTimeInterval(0.45)
        reposition()
        redrawPanels()
        let token = UUID()
        pendingLayoutRefreshToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, self.pendingLayoutRefreshToken == token else { return }
            self.pendingLayoutRefreshToken = nil
            self.settingsRefreshPauseUntil = nil
            self.refresh()
        }
    }

    private func setFavoriteHoverActivity(_ isActive: Bool) {
        // AX enumeration can block the main thread long enough to interrupt the Dock wave.
        // Remain paused while the pointer rests on the icons, and briefly after
        // it exits. The active deadline recovers if macOS misses mouseExited.
        let now = Date()
        if isActive {
            favoriteHoverActiveUntil = now.addingTimeInterval(10)
            favoriteHoverRefreshPauseUntil = nil
        } else {
            favoriteHoverActiveUntil = nil
            favoriteHoverRefreshPauseUntil = now.addingTimeInterval(1.5)
        }
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

    private func hideInDock() {
        setOptionShortcutsVisible(false)
        stopRegisteredHotKeys()
        isHiddenInDock = true
        synchronizeSystemDockVisibility()
        dockRestoreAvailableAt = Date().addingTimeInterval(0.8)
        settingsWindowController?.hide()
        windowService.clearWindowSpaceReservations(restore: true, windows: windows)
        NSApp.setActivationPolicy(.regular)
        panel?.orderOut(nil)
        dockFinderPanel?.orderOut(nil)
    }

    private func synchronizeSystemDockVisibility() {
        if isHiddenInDock {
            systemDockVisibility.restore()
        } else {
            systemDockVisibility.synchronize(hidden: settings.layoutMode == .taskbar)
        }
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
        let recentState = recentApplications.map(\.id).joined(separator: "\u{1F}")
        let runningState = runningApplicationIDs.sorted().joined(separator: "\u{1F}")
        let fusionState = settings.layoutMode == .dockCompanion
            ? dockCompanionWindows.map(\.id).joined(separator: "\u{1F}") : ""
        return "\(isTrusted)|\(settings.layoutMode.rawValue)|\(!bulkMinimizedWindows.isEmpty)|\(windowState)|\(recentState)|\(runningState)|\(fusionState)"
    }

    private func updateRecentWindowFocus() {
        let now = Date()
        let liveIDs = Set(windows.map(\.id))
        recentWindowFocusDates = recentWindowFocusDates.filter {
            liveIDs.contains($0.key) && now.timeIntervalSince($0.value) <= FusionDisplayPolicy.recentLifetime
        }
        let focusedID = windows.first(where: \.isFocused)?.id
        if let focusedID {
            recentWindowFocusDates[focusedID] = now
        }
    }

    private func fusionShortcutWindows(for displayedWindows: [WindowModel]) -> [WindowModel] {
        let ordered = settings.orderedWindows(displayedWindows)
        let grouped = Dictionary(grouping: ordered, by: \.appKey)
        var seen = Set<String>()
        return ordered.compactMap { window in
            guard let group = grouped[window.appKey] else { return nil }
            if group.count >= settings.dockCompanionCollapseThreshold {
                guard seen.insert(window.appKey).inserted else { return nil }
                return group.first(where: \.isFocused) ?? group[0]
            }
            return window
        }
    }

    private func appKey(for application: NSRunningApplication) -> String? {
        guard application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              !application.isTerminated else { return nil }
        if let bundleIdentifier = application.bundleIdentifier, !bundleIdentifier.isEmpty {
            return bundleIdentifier
        }
        guard let name = application.localizedName, !name.isEmpty else { return nil }
        return "name:\(name)"
    }

    private func recentApp(for application: NSRunningApplication) -> FavoriteApp? {
        guard application.activationPolicy == .regular,
              let id = appKey(for: application),
              let name = application.localizedName else { return nil }
        guard !settings.blacklistedAppKeys.contains(id) else { return nil }
        return FavoriteApp(
            id: id,
            bundleIdentifier: application.bundleIdentifier,
            applicationName: name,
            bundlePath: application.bundleURL?.path
        )
    }

    private func seedRecentApplications() {
        let running = NSWorkspace.shared.runningApplications
            .sorted { ($0.launchDate ?? .distantPast) < ($1.launchDate ?? .distantPast) }
        for application in running {
            guard let recent = recentApp(for: application),
                  !settings.recentApps.contains(where: { $0.id == recent.id }) else { continue }
            settings.recordRecentApp(recent)
        }
        refreshRecentApplications()
    }

    private func refreshRecentApplications() {
        runningApplicationIDs = Set(NSWorkspace.shared.runningApplications.compactMap(appKey(for:)))
        recentApplications = RecentAppDisplayPolicy.visible(
            from: settings.recentApps,
            excluding: { settings.isFavorite($0.id) }
        )
    }

    private func refreshFavoriteBadgesIfNeeded() {
        guard settings.layoutMode == .taskbar, !isHiddenInDock,
              permissionService.isTrusted, !settings.favoriteApps.isEmpty else {
            favoriteBadges.update([:])
            return
        }
        let now = Date()
        guard !badgePollInFlight,
              now.timeIntervalSince(lastBadgePollAt) >= 2,
              favoriteHoverActiveUntil.map({ $0 <= now }) ?? true,
              let dockPID = NSRunningApplication.runningApplications(
                  withBundleIdentifier: "com.apple.dock"
              ).first?.processIdentifier else { return }
        lastBadgePollAt = now
        badgePollInFlight = true
        let favorites = settings.favoriteApps
        badgePollQueue.async { [weak self] in
            let badges = DockBadgeService.badges(for: favorites, dockPID: dockPID)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.badgePollInFlight = false
                guard self.settings.layoutMode == .taskbar, !self.isHiddenInDock else { return }
                self.favoriteBadges.update(badges)
            }
        }
    }

    private func quitRecentApp(_ recent: FavoriteApp) {
        for application in NSWorkspace.shared.runningApplications {
            guard appKey(for: application) == recent.id else { continue }
            _ = application.terminate()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.refresh()
        }
    }

    private func updateWindowSpaceReservations(force: Bool) {
        guard let panel,
              let screen = panel.screen ?? NSScreen.screens.first else { return }
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
        } else {
            reservationPanelFrame = CGRect(
                x: panel.frame.minX,
                y: panel.frame.minY,
                width: panel.frame.width,
                height: settings.layoutMode == .dockCompanion ? settings.dockCompanionHeight : settings.taskbarHeight
            )
        }
        let context = ReservationContext(
            panelFrame: reservationPanelFrame,
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            enabled: !isHiddenInDock && panel.isVisible,
            layoutMode: settings.layoutMode
        )
        let now = Date()
        guard force || context != lastReservationContext
                || now.timeIntervalSince(lastReservationUpdateAt) >= 1.5 else { return }
        lastReservationContext = context
        lastReservationUpdateAt = now
        guard context.enabled else {
            windowService.clearWindowSpaceReservations(restore: true, windows: [])
            return
        }
        let reservationWindows = windowService.enumerateWindows(
            excludingPID: ProcessInfo.processInfo.processIdentifier,
            showHiddenApps: true,
            blacklistedAppKeys: [],
            blockedWindowRules: []
        )
        windowService.updateWindowSpaceReservations(
            for: reservationWindows,
            panelFrame: reservationPanelFrame,
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            enabled: true
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
        if notification.name == NSWorkspace.didLaunchApplicationNotification
            || notification.name == NSWorkspace.didActivateApplicationNotification,
           let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
           let recent = recentApp(for: application) {
            settings.recordRecentApp(recent)
        }
        refresh()
        guard notification.name == NSWorkspace.didActivateApplicationNotification else { return }
        // Alt-Tab helpers can publish app activation just before Accessibility updates
        // AXMainWindow. Refresh once more after that short hand-off settles.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.refresh()
        }
    }
}
