import AppKit
import Combine
import QuartzCore
import SwiftUI
import TaskDockBrowserProtocol

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
        var observedWindowIDs: Set<String> = []
    }

    private let permissionService = AccessibilityPermissionService()
    private let windowService = AXWindowService()
    private let dockGeometryService = DockGeometryService()
    private let settings = SettingsStore()
    private let dockFavoritesSync = DockFavoritesSyncService()
    private var lastDockFavoritesPollAt = Date.distantPast
    private var lastDockFavoritesSnapshot: DockFavoritesSyncService.Snapshot?
    private var pendingDockFavoritesPush: DispatchWorkItem?
    private let systemDockVisibility = SystemDockVisibilityController()
    private let trashStatus = TrashStatusService()
    private let favoriteBadges = FavoriteBadgeStore()
    private let windowProgress = WindowProgressStore()
    private let progressScanner = WindowProgressScanner()
    private let license: LicenseService
    private let onOpenLicense: () -> Void
    private var licenseObservation: AnyCancellable?
    private var hasLicenseAccess: Bool { license.isUnlocked || LicenseStatus.hasValidPurchase }
    private let collapseAnimator = TaskbarCollapseAnimator()
    private let badgePollQueue = DispatchQueue(label: "taskdock.dock-badges", qos: .utility)
    private let progressPollQueue = DispatchQueue(label: "taskdock.window-progress", qos: .utility)
    private var panel: NSPanel?
    private var timer: Timer?
    private var pointerAvoidanceTimer: Timer?
    private var lastPointerAvoidanceCheckAt = Date.distantPast
    private var pointerWasInAvoidanceRegion = false
    private var progressTimer: Timer?
    private var progressPollInFlight = false
    private var progressPollGeneration = 0
    private var windows: [WindowModel] = []
    private let bulkVisibility = ApplicationVisibilityToggle()
    private var taskbarHiddenPIDs: Set<pid_t> = []
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
    private var nextFocusObserverAttemptAt: [pid_t: Date] = [:]
    private var lastFocusObserverSyncAt = Date.distantPast
    private var appliedLayoutMode: TaskDockLayoutMode?
    private var stableDockGeometry: DockGeometrySnapshot?
    private var pendingDockGeometry: DockGeometrySnapshot?
    private var pendingDockGeometrySince: Date?

    private static let focusObserverCallback: AXObserverCallback = { _, element, notification, context in
        guard let context else { return }
        let controller = Unmanaged<TaskbarPanelController>.fromOpaque(context).takeUnretainedValue()
        Task { @MainActor [weak controller] in
            controller?.windowService.observeWindowLifecycle(element, notification: notification as String)
            controller?.refresh()
        }
    }

    init(license: LicenseService, onOpenLicense: @escaping () -> Void) {
        self.license = license
        self.onOpenLicense = onOpenLicense
    }

    func show() {
        settings.onFavoritesChanged = { [weak self] in self?.scheduleFavoritesPush() }
        pollDockFavorites(force: true)
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
            self?.performTrialAction { self?.toggleAllAppVisibility() }
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
        progressTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollWindowProgress() }
        }
        let avoidanceTimer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkPointerWindowAvoidance() }
        }
        RunLoop.main.add(avoidanceTimer, forMode: .common)
        pointerAvoidanceTimer = avoidanceTimer
        pollWindowProgress()
        let workspaceNotifications = NSWorkspace.shared.notificationCenter
        workspaceNotifications.addObserver(self, selector: #selector(workspaceChanged), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        workspaceNotifications.addObserver(self, selector: #selector(workspaceChanged), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        workspaceNotifications.addObserver(self, selector: #selector(workspaceChanged), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        workspaceNotifications.addObserver(self, selector: #selector(workspaceChanged), name: NSWorkspace.didHideApplicationNotification, object: nil)
        workspaceNotifications.addObserver(self, selector: #selector(workspaceChanged), name: NSWorkspace.didUnhideApplicationNotification, object: nil)
        syncAppFocusObservers(force: true)
        licenseObservation = license.$isUnlocked.removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.licenseAccessChanged() }
    }

    func stop() {
        licenseObservation?.cancel()
        licenseObservation = nil
        pendingDockFavoritesPush?.cancel()
        pendingDockFavoritesPush = nil
        settings.onFavoritesChanged = nil
        bulkVisibility.restore()
        for pid in taskbarHiddenPIDs {
            NSRunningApplication(processIdentifier: pid)?.unhide()
        }
        taskbarHiddenPIDs = []
        minimizeHotKeyMonitor?.stop()
        minimizeHotKeyMonitor = nil
        systemDockVisibility.restore()
        pendingLayoutRefreshToken = nil
        timer?.invalidate()
        pointerAvoidanceTimer?.invalidate()
        pointerAvoidanceTimer = nil
        progressTimer?.invalidate()
        progressTimer = nil
        progressPollGeneration += 1
        progressPollInFlight = false
        windowProgress.update([:])
        let scanner = progressScanner
        progressPollQueue.async { scanner.clear() }
        shortcutMonitor?.stop()
        stopRegisteredHotKeys()
        settings.activeTaskbarShortcutIndices = []
        settings.activeFavoriteShortcutIndices = []
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        removeAllAppFocusObservers()
        nextFocusObserverAttemptAt.removeAll()
        lastFocusObserverSyncAt = .distantPast
        windowService.clearWindowSpaceReservations(restore: true, windows: windows)
        panel?.orderOut(nil)
        dockFinderPanel?.orderOut(nil)
    }

    func restoreFromDock() {
        guard isHiddenInDock, Date() >= dockRestoreAvailableAt else { return }
        isHiddenInDock = false
        NSApp.setActivationPolicy(.accessory)
        refresh()
        if hasLicenseAccess { panel?.orderFrontRegardless() }
        if hasLicenseAccess, settings.layoutMode == .dockCompanion, !finderWindows.isEmpty {
            dockFinderPanel?.orderFrontRegardless()
        }
    }

    var currentLayoutMode: TaskDockLayoutMode { settings.layoutMode }
    var isTaskDockHidden: Bool { isHiddenInDock }
    var canRestoreHiddenApplications: Bool {
        bulkVisibility.canRestore
    }

    func toggleAllApplications() {
        performTrialAction { toggleAllAppVisibility() }
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
        panel.appearance = settings.layoutMode == .taskbar ? nil : NSAppearance(named: .darkAqua)
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
            windowProgress: windowProgress,
            isAccessibilityTrusted: permissionService.isTrusted,
            canRestoreHiddenApplications: canRestoreHiddenApplications,
            onRequestPermission: { [weak self] in self?.requestPermission() },
            onSelect: { [weak self] window in self?.performTrialAction { self?.select(window) } },
            onToggleAllApplications: { [weak self] in self?.performTrialAction { self?.toggleAllAppVisibility() } },
            onOpenTrash: { [weak self] in self?.performTrialAction { self?.openTrash() } },
            onEmptyTrash: { [weak self] in self?.performTrialAction { self?.emptyTrash() } },
            onRestoreLatestTrashItem: { [weak self] in self?.performTrialAction { self?.restoreLatestTrashItem() } },
            onOpenFolder: { [weak self] folder in
                self?.performTrialAction { NSWorkspace.shared.open(folder.url) }
            },
            onShowAppWindows: { [weak self] window in self?.performTrialAction { self?.showAppWindows(for: window) } },
            onBlockWindowType: { [weak self] window in self?.performTrialAction { self?.blockWindowType(window) } },
            onClose: { [weak self] window in self?.performTrialAction { self?.close(window) } },
            onOpenFavorite: { [weak self] favorite in self?.performTrialAction { self?.openFavorite(favorite) } },
            onPerformWindowAction: { [weak self] action in self?.performTrialAction(action) },
            onQuitRecentApp: { [weak self] favorite in self?.performTrialAction { self?.quitRecentApp(favorite) } },
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

    private func performTrialAction(_ action: () -> Void) {
        guard hasLicenseAccess else {
            onOpenLicense()
            return
        }
        action()
    }

    private func reposition(
        animated: Bool = false,
        animationDuration: TimeInterval = 0.16,
        animationTimingFunction: CAMediaTimingFunction? = nil
    ) {
        guard let screen = NSScreen.screens.first, panel != nil else { return }
        let screenFrame = screen.frame

        if appliedLayoutMode != settings.layoutMode {
            windowService.clearWindowSpaceReservations(restore: true, windows: [])
            pointerWasInAvoidanceRegion = false
            appliedLayoutMode = settings.layoutMode
            let appearance = settings.layoutMode == .taskbar ? nil : NSAppearance(named: .darkAqua)
            panel?.appearance = appearance
            dockFinderPanel?.appearance = appearance
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
        let origin = NSPoint(x: screenFrame.minX, y: screenFrame.minY)
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
        let shelfApps = isDockCompanion ? settings.favoriteApps : settings.displayedFavoriteApps
        let favoriteWidth: CGFloat
        if !showsFavorites {
            favoriteWidth = 0
        } else if isDockCompanion {
            favoriteWidth = shelfApps.isEmpty ? 0
                : CGFloat(shelfApps.count) * 32
                    + CGFloat(max(shelfApps.count - 1, 0)) * 2 + 14
        } else {
            favoriteWidth = TaskbarFavoriteLaneLayout.contentWidth(
                appCount: shelfApps.count,
                folderCount: showsControls ? settings.favoriteFolders.count : 0,
                showsTrash: showsControls) + 5
        }
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
        // Avoid a full AX scan competing with the brief window animation.
        if windowService.isAnimatingPointerAvoidance { return }
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
            taskbarHiddenPIDs: taskbarHiddenPIDs,
            blacklistedAppKeys: settings.blacklistedAppKeys,
            blockedWindowRules: settings.blockedWindowRules,
            finderTabsAsWindows: settings.finderTabsAsWindows
        )
        // Some apps omit a minimized window from AXWindows. A closed WeChat
        // window must not be kept as a minimized task merely because the app
        // process remains running.
        let refreshedIDs = Set(refreshedWindows.map(\.id))
        let refreshedWeChatPIDs = Set(refreshedWindows.filter {
            $0.bundleIdentifier == "com.tencent.xinWeChat"
        }.map(\.pid))
        let retainedWindows = windows.filter {
            guard !refreshedIDs.contains($0.id),
                  let app = NSRunningApplication(processIdentifier: $0.pid) else { return false }
            // A past minimize click is not evidence that a window still exists:
            // it may have been restored externally and then closed with Command-W.
            if $0.bundleIdentifier == "com.tencent.xinWeChat" {
                return !refreshedWeChatPIDs.contains($0.pid) && windowService.isMinimized($0)
            }
            return (taskbarHiddenPIDs.contains($0.pid) && app.isHidden) ||
                windowService.isMinimized($0)
        }.map { window in
            return WindowModel(
                id: window.id, nativeWindowID: window.nativeWindowID, pid: window.pid,
                bundleIdentifier: window.bundleIdentifier, applicationName: window.applicationName,
                applicationIcon: window.applicationIcon, rawTitle: window.rawTitle, title: window.title,
                accessibilityRole: window.accessibilityRole, accessibilitySubrole: window.accessibilitySubrole,
                isMinimized: true, isFocused: false,
                isMain: window.isMain,
                axWindow: window.axWindow, finderTab: window.finderTab
            )
        }
        windows = refreshedWindows + retainedWindows
        observeWindowLifecycles(windows)
        synchronizeBulkVisibilityState()
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
        if isHiddenInDock || !hasLicenseAccess {
            panel?.orderOut(nil)
            dockFinderPanel?.orderOut(nil)
        } else if settings.layoutMode != .dockCompanion || settings.dockCompanionShowsBottomBar || !otherWindows.isEmpty {
            if panel?.isVisible != true {
                panel?.orderFrontRegardless()
            }
        } else {
            panel?.orderOut(nil)
        }
        if !isHiddenInDock, hasLicenseAccess, settings.layoutMode == .dockCompanion, !finderWindows.isEmpty {
            if dockFinderPanel?.isVisible != true { dockFinderPanel?.orderFrontRegardless() }
        } else {
            dockFinderPanel?.orderOut(nil)
        }
    }

    private func requestPermission() { permissionService.requestAccess(); refresh() }
    private func select(_ window: WindowModel) {
        if settings.layoutMode == .taskbar {
            toggleTaskbarWindow(window, animate: true)
            return
        }
        _ = windowService.toggle(window)
        refreshAfterWindowAction()
    }

    private func toggleTaskbarWindow(_ window: WindowModel, animate: Bool) {
        guard let app = NSRunningApplication(processIdentifier: window.pid) else { return }
        let isWeChat = window.bundleIdentifier == "com.tencent.xinWeChat"
        let isMultiWindowApp = Set(windows.filter { $0.pid == window.pid }.map(\.nativeWindowID)).count > 1
        let needsWindowMinimization = isWeChat || isMultiWindowApp ||
            window.bundleIdentifier == "com.microsoft.Excel" ||
            window.bundleIdentifier == "com.apple.finder"
        if app.isHidden {
            taskbarHiddenPIDs.remove(window.pid)
            _ = windowService.activate(window)
            reopenIfNoWindowAppears(app)
        } else if !windowService.isMinimized(window) &&
                    (isWeChat ? window.isFocused : windowService.isCurrentlyFocused(window)) {
            // Prefer real window minimization for every app, including single-window
            // apps. App hiding has no native window-collapse animation.
            if !windowService.minimize(window) && !needsWindowMinimization {
                let frame = animate ? windowService.frame(of: window) : nil
                let target = NSEvent.mouseLocation
                if app.hide() {
                    taskbarHiddenPIDs.insert(window.pid)
                    if animate, panel?.frame.contains(target) == true {
                        collapseAnimator.collapse(window: window, from: frame, toward: target)
                    }
                }
            }
        } else {
            taskbarHiddenPIDs.remove(window.pid)
            _ = windowService.activate(window)
            reopenIfNoWindowAppears(app)
        }
        refreshAfterWindowAction()
    }

    private func reopenIfNoWindowAppears(_ app: NSRunningApplication) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self, weak app] in
            guard let self, let app, !app.isTerminated,
                  !app.isHidden, !self.windowService.hasOnscreenWindow(for: app.processIdentifier) else { return }
            _ = self.windowService.reopenApplication(app)
            self.refreshAfterWindowAction()
        }
    }

    private func setOptionShortcutsVisible(_ visible: Bool) {
        let shouldShow = visible && !isHiddenInDock && hasLicenseAccess && permissionService.isTrusted
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
              hasLicenseAccess,
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
            isCompanion ? fusionShortcutWindows(for: finderWindows).count : settings.displayedFavoriteApps.count,
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
        performTrialAction { select(ordered[index - 1]) }
    }

    private func openShortcutFavorite(_ index: Int) {
        guard !isHiddenInDock,
              registeredOptionShortcuts.favorites.contains(index),
              index > 0 else { return }
        if settings.layoutMode == .dockCompanion {
            let ordered = fusionShortcutWindows(for: finderWindows)
            guard ordered.indices.contains(index - 1) else { return }
            performTrialAction { select(ordered[index - 1]) }
            return
        }
        let shelfApps = settings.displayedFavoriteApps
        guard shelfApps.indices.contains(index - 1) else { return }
        let favorite = shelfApps[index - 1]
        let focusedWindow = windows.first { window in
            windowService.isCurrentlyFocused(window) && (
                favorite.bundleIdentifier.map { $0 == window.bundleIdentifier } ?? false ||
                favorite.bundleIdentifier == nil && window.applicationName == favorite.applicationName
            )
        }
        performTrialAction {
            if let focusedWindow {
                select(focusedWindow)
            } else {
                openFavorite(favorite)
            }
        }
    }
    private func toggleAllAppVisibility() {
        synchronizeBulkVisibilityState()
        if bulkVisibility.canRestore {
            let restoredPIDs = bulkVisibility.hiddenPIDs
            bulkVisibility.restore()
            taskbarHiddenPIDs.subtract(restoredPIDs)
        } else {
            bulkVisibility.hide()
            taskbarHiddenPIDs.formUnion(bulkVisibility.hiddenPIDs)
        }
        refreshAfterWindowAction()
    }

    private func synchronizeBulkVisibilityState() {
        bulkVisibility.synchronize()
        taskbarHiddenPIDs = taskbarHiddenPIDs.filter {
            NSRunningApplication(processIdentifier: $0)?.isHidden == true
        }
        taskbarHiddenPIDs.formUnion(bulkVisibility.hiddenPIDs)
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
                license: license,
                onOpenLicense: onOpenLicense,
                onChanged: { [weak self] in
                    guard let self else { return }
                    self.pendingLayoutRefreshToken = nil
                    self.settingsRefreshPauseUntil = nil
                    if self.shortcutMonitor?.isOptionShortcutActive == true {
                        self.setOptionShortcutsVisible(true)
                    }
                    self.lastRenderedWindowSignature = ""
                    self.pollDockFavorites(force: true)
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
        pollDockFavorites()
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

    private func pollDockFavorites(force: Bool = false) {
        guard settings.dockFavoritesSyncEnabled else {
            lastDockFavoritesSnapshot = nil
            settings.replaceDockTransientApps([])
            return
        }
        if pendingDockFavoritesPush != nil && !force { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastDockFavoritesPollAt) >= 2 else { return }
        lastDockFavoritesPollAt = now
        do {
            let snapshot = try dockFavoritesSync.read()
            let transientApps = dockFavoritesSync.visibleUnpinnedApps(pinnedApps: snapshot.apps)
            let transientChanged = transientApps.map { $0 != settings.dockTransientApps } ?? false
            if force || snapshot != lastDockFavoritesSnapshot || transientChanged {
                lastDockFavoritesSnapshot = snapshot
                settings.replaceFavoritesFromDock(apps: snapshot.apps, folders: snapshot.folders)
                if let transientApps { settings.replaceDockTransientApps(transientApps) }
                refreshRecentApplications()
                synchronizeHotKeys()
                reposition()
                redrawPanels()
            }
            settings.dockFavoritesSyncError = nil
        } catch {
            settings.dockFavoritesSyncError = error.localizedDescription
        }
    }

    private func scheduleFavoritesPush() {
        pendingDockFavoritesPush?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pendingDockFavoritesPush = nil
            self?.pushFavoritesToDock()
        }
        pendingDockFavoritesPush = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func pushFavoritesToDock() {
        guard settings.dockFavoritesSyncEnabled else { return }
        do {
            let desired = DockFavoritesSyncService.Snapshot(
                apps: settings.favoriteApps,
                folders: settings.favoriteFolders
            )
            let actual = try dockFavoritesSync.write(desired)
            lastDockFavoritesSnapshot = actual
            lastDockFavoritesPollAt = Date()
            settings.replaceFavoritesFromDock(apps: actual.apps, folders: actual.folders)
            settings.dockFavoritesSyncError = nil
            reposition()
            redrawPanels()
        } catch {
            pollDockFavorites(force: true)
            settings.dockFavoritesSyncError = error.localizedDescription
        }
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
            systemDockVisibility.synchronize(
                hidden: settings.layoutMode == .taskbar, accessAllowed: hasLicenseAccess)
        }
    }

    private func licenseAccessChanged() {
        if !hasLicenseAccess {
            // Return control to the native Dock even while a drag or popover
            // temporarily pauses normal taskbar refreshes.
            for pid in taskbarHiddenPIDs {
                NSRunningApplication(processIdentifier: pid)?.unhide()
            }
            taskbarHiddenPIDs.removeAll()
            setOptionShortcutsVisible(false)
            stopRegisteredHotKeys()
            windowService.clearWindowSpaceReservations(restore: true, windows: windows)
            lastReservationContext = nil
            panel?.orderOut(nil)
            dockFinderPanel?.orderOut(nil)
        }
        synchronizeSystemDockVisibility()
        lastRenderedWindowSignature = ""
        refresh()
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
        return "\(isTrusted)|\(settings.layoutMode.rawValue)|\(bulkVisibility.canRestore)|\(windowState)|\(recentState)|\(runningState)|\(fusionState)"
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
        let displayedIDs = Set(settings.displayedFavoriteApps.map(\.id))
        recentApplications = RecentAppDisplayPolicy.visible(
            from: settings.recentApps,
            excluding: { displayedIDs.contains($0.id) }
        )
    }

    private func refreshFavoriteBadgesIfNeeded() {
        guard settings.layoutMode == .taskbar, !isHiddenInDock,
              permissionService.isTrusted, !settings.displayedFavoriteApps.isEmpty else {
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
        let favorites = settings.displayedFavoriteApps
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

    private func pollWindowProgress() {
        guard settings.layoutMode == .taskbar, !isHiddenInDock,
              permissionService.isTrusted, !progressPollInFlight else {
            if settings.layoutMode != .taskbar || isHiddenInDock { windowProgress.update([:]) }
            return
        }
        var seen = Set<String>()
        let candidates = windows.compactMap { window -> WindowProgressCandidate? in
            guard seen.insert(window.nativeWindowID).inserted else { return nil }
            return WindowProgressCandidate(
                id: window.nativeWindowID, pid: window.pid,
                bundleIdentifier: window.bundleIdentifier,
                isFocused: window.isFocused, window: window.axWindow
            )
        }
        progressPollInFlight = true
        let generation = progressPollGeneration
        let scanner = progressScanner
        progressPollQueue.async { [weak self] in
            let downloads = BrowserProgressStore().tasks()
            let progress = scanner.scan(candidates)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.progressPollGeneration == generation else { return }
                self.progressPollInFlight = false
                guard self.settings.layoutMode == .taskbar, !self.isHiddenInDock else { return }
                let currentIDs = Set(self.windows.map(\.nativeWindowID))
                self.windowProgress.update(progress.filter { currentIDs.contains($0.key) })
                self.windowProgress.updateDownloads(downloads)
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

    private func checkPointerWindowAvoidance() {
        guard !windowService.isAnimatingPointerAvoidance else { return }
        guard settings.layoutMode == .taskbar, hasLicenseAccess, permissionService.isTrusted,
              !isHiddenInDock, let panel, panel.isVisible,
              let screen = panel.screen ?? NSScreen.screens.first,
              let desktopTop = NSScreen.screens.first?.frame.maxY else { return }
        let inside = PointerWindowAvoidanceGeometry.isInTriggerRegion(
            pointer: NSEvent.mouseLocation, screen: screen.frame)
        let justEnteredRegion = inside && !pointerWasInAvoidanceRegion
        pointerWasInAvoidanceRegion = inside
        let now = Date()
        guard NSEvent.pressedMouseButtons == 0,
              reorderRefreshPauseUntil.map({ $0 <= now }) ?? true,
              settingsRefreshPauseUntil.map({ $0 <= now }) ?? true else { return }
        guard justEnteredRegion || now.timeIntervalSince(lastPointerAvoidanceCheckAt) >= 0.8 else { return }
        lastPointerAvoidanceCheckAt = now
        let inset = settings.taskbarSideInset
        let bar = CGRect(x: panel.frame.minX + inset, y: panel.frame.minY + 4,
            width: max(0, panel.frame.width - 2 * inset), height: settings.taskbarHeight)
        let visibleWindows = windowService.enumerateWindows(
            excludingPID: ProcessInfo.processInfo.processIdentifier,
            showHiddenApps: false, blacklistedAppKeys: [], blockedWindowRules: [])
        windowService.moveWindowsAboveTaskbar(visibleWindows, panelFrame: bar,
            screenFrame: screen.frame, visibleFrame: screen.visibleFrame, desktopTop: desktopTop,
            includeOrdinaryWindows: inside)
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
                height: settings.layoutMode == .dockCompanion ? settings.dockCompanionHeight : settings.taskbarHeight + 4
            )
        }
        let context = ReservationContext(
            panelFrame: reservationPanelFrame,
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            enabled: !isHiddenInDock && hasLicenseAccess && panel.isVisible,
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
        // Taskbar avoidance uses a single bounded bottom-retraction manager:
        // tiled windows by default, ordinary windows when the pointer is near the bottom. Do not let the legacy maximized-window
        // manager resize windows before the pointer or bypass its off-screen guard.
        guard settings.layoutMode != .taskbar else { return }
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
            clearance: settings.layoutMode == .taskbar ? 6 : 2,
            enabled: true
        )
    }

    private func syncAppFocusObservers(force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastFocusObserverSyncAt) >= 5 else { return }
        lastFocusObserverSyncAt = now
        guard permissionService.isTrusted else {
            removeAllAppFocusObservers()
            nextFocusObserverAttemptAt.removeAll()
            return
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let currentPIDs = Set(NSWorkspace.shared.runningApplications
            .filter { $0.processIdentifier != ownPID && $0.activationPolicy == .regular }
            .map(\.processIdentifier))

        for pid in appFocusObservers.keys where !currentPIDs.contains(pid) {
            removeAppFocusObserver(for: pid)
        }
        nextFocusObserverAttemptAt = nextFocusObserverAttemptAt.filter { currentPIDs.contains($0.key) }

        for pid in currentPIDs where appFocusObservers[pid] == nil {
            guard nextFocusObserverAttemptAt[pid].map({ $0 <= now }) ?? true else { continue }
            // An app can briefly reject AXObserver registration while launching.
            // Retry later without blocking every 0.7-second taskbar refresh.
            nextFocusObserverAttemptAt[pid] = now.addingTimeInterval(10)
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
            nextFocusObserverAttemptAt.removeValue(forKey: pid)
        }
    }

    private func observeWindowLifecycles(_ windows: [WindowModel]) {
        let context = Unmanaged.passUnretained(self).toOpaque()
        for window in windows {
            guard var entry = appFocusObservers[window.pid],
                  !entry.observedWindowIDs.contains(window.nativeWindowID) else { continue }
            let notifications = [kAXWindowMiniaturizedNotification,
                                 kAXWindowDeminiaturizedNotification,
                                 kAXUIElementDestroyedNotification]
            for notification in notifications {
                _ = AXObserverAddNotification(entry.observer, window.axWindow,
                    notification as CFString, context)
            }
            // Destruction is supported by normal window elements; do not repeatedly
            // retry unsupported notifications on every refresh.
            entry.observedWindowIDs.insert(window.nativeWindowID)
            appFocusObservers[window.pid] = entry
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
            || notification.name == NSWorkspace.didTerminateApplicationNotification {
            syncAppFocusObservers(force: true)
        }
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
