import AppKit
import ApplicationServices
import Carbon
import os.log

final class AXWindowService {
    private struct ReservedWindowFrame {
        let window: AXUIElement
        let original: CGRect
        var applied: CGRect
        var lastAdjustmentAt = Date()
    }

    private struct ScreenWindow {
        let pid: pid_t
        let frame: CGRect
        let title: String
    }

    private let logger = Logger(subsystem: "com.taskdock.app", category: "accessibility")
    private var windowOrder: [String: Int] = [:]
    private var nextWindowOrder = 0
    private var knownFinderDocumentWindows: [AXUIElement] = []
    private var hasEnumeratedFinderWindows = false
    private var windowEvidence: [String: MinimizedWindowEvidence] = [:]

    private func evidenceKey(_ window: AXUIElement) -> String? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success else { return nil }
        return "\(pid)-\(CFHash(window))"
    }

    func observeWindowLifecycle(_ element: AXUIElement, notification: String) {
        guard let key = evidenceKey(element) else { return }
        var evidence = windowEvidence[key] ?? MinimizedWindowEvidence()
        switch notification {
        case kAXWindowMiniaturizedNotification: evidence.observeMiniaturized()
        case kAXWindowDeminiaturizedNotification: evidence.observeRestored()
        case kAXUIElementDestroyedNotification: evidence.observeDestroyed()
        default: return
        }
        windowEvidence[key] = evidence
    }

    private func hasMinimizedEvidence(_ window: AXUIElement) -> Bool {
        guard let key = evidenceKey(window) else { return false }
        var evidence = windowEvidence[key] ?? MinimizedWindowEvidence()
        let value = copyAttribute(window, kAXMinimizedAttribute) as? Bool
        let result = evidence.resolve(liveValue: value,
            isLiveWindow: (copyAttribute(window, kAXRoleAttribute) as? String) == kAXWindowRole)
        windowEvidence[key] = evidence
        return result
    }
    private var pointerAvoidedFrames: [String: ReservedWindowFrame] = [:]
    private var pointerSuppressedFrames: [String: CGRect] = [:]
    private var pointerSuppressedAt: [String: Date] = [:]
    private var pointerDefaultRetries: [String: Int] = [:]
    private var pointerDefaultLayoutFrames: [String: CGRect] = [:]
    private var pointerCandidateFrames: [String: (frame: CGRect, since: Date)] = [:]
    private func suppressPointerAvoidance(_ id: String, frame: CGRect) {
        pointerSuppressedFrames[id] = frame
        pointerSuppressedAt[id] = Date()
    }
    private var activePointerRetractions: [String: UUID] = [:]
    var isAnimatingPointerAvoidance: Bool { !activePointerRetractions.isEmpty }
    private var reservedWindowFrames: [String: ReservedWindowFrame] = [:]
    private var activeWindowLifts: [String: UUID] = [:]
    private var liftSuppressedFrames: [String: CGRect] = [:]
    private var activationRequestID = UUID()
    private var recentActivation: (windowID: String, date: Date)?
    private let ignoredWindowTitles: [String: Set<String>] = [
        "com.openai.codex": ["computer use", "computer use controls"]
    ]

    func enumerateWindows(
        excludingPID: pid_t,
        showHiddenApps: Bool,
        taskbarHiddenPIDs: Set<pid_t> = [],
        blacklistedAppKeys: Set<String>,
        blockedWindowRules: [BlockedWindowRule],
        finderTabsAsWindows: Bool = false
    ) -> [WindowModel] {
        guard AXIsProcessTrusted() else { return [] }
        var result: [WindowModel] = []
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        let runningApps = NSWorkspace.shared.runningApplications
            .filter {
                $0.processIdentifier != excludingPID &&
                !WindowFilterRules.shouldIgnoreApplication(bundleIdentifier: $0.bundleIdentifier) &&
                $0.activationPolicy == .regular &&
                (showHiddenApps || !$0.isHidden || taskbarHiddenPIDs.contains($0.processIdentifier))
            }
            .sorted {
                ($0.launchDate ?? .distantPast) < ($1.launchDate ?? .distantPast)
            }
        let runningPIDs = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
        windowEvidence = windowEvidence.filter { key, _ in
            key.split(separator: "-").first.flatMap { Int32($0) }.map { runningPIDs.contains($0) } ?? false
        }
        let topmostWindow = frontmostPID.flatMap { topmostScreenWindow(for: $0) }

        for app in runningApps {
            let pid = app.processIdentifier
            let applicationName = app.localizedName ?? "Unknown App"
            let appKey = app.bundleIdentifier.map { $0 } ?? "name:\(applicationName)"
            if blacklistedAppKeys.contains(appKey) { continue }
            let axApp = AXUIElementCreateApplication(pid)
            guard let values = copyAttribute(axApp, kAXWindowsAttribute) as? [AXUIElement] else { continue }
            let focusedWindow = copyAttribute(axApp, kAXFocusedWindowAttribute)
            let mainWindow = copyAttribute(axApp, kAXMainWindowAttribute)
            let displayableWindows = values.filter {
                shouldIncludeWindow(
                    $0,
                    bundleIdentifier: app.bundleIdentifier,
                    appKey: appKey,
                    blockedWindowRules: blockedWindowRules
                )
            }
            if app.bundleIdentifier == "com.apple.finder", !knownFinderDocumentWindows.isEmpty {
                hasEnumeratedFinderWindows = true
            }
            let topmostAXWindow: AXUIElement? = topmostWindow.flatMap { screenWindow in
                guard screenWindow.pid == pid else { return nil }
                return matchingWindow(for: screenWindow, among: displayableWindows)
            }

            var appWindows: [(order: Int, tabIndex: Int, model: WindowModel)] = []
            for axWindow in displayableWindows {
                let title = (copyAttribute(axWindow, kAXTitleAttribute) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let role = copyAttribute(axWindow, kAXRoleAttribute) as? String ?? ""
                let subrole = copyAttribute(axWindow, kAXSubroleAttribute) as? String

                let main = (copyAttribute(axWindow, kAXMainAttribute) as? Bool) ?? false
                let minimized = hasMinimizedEvidence(axWindow)
                let matchesFocusedWindow = focusedWindow.map { CFEqual($0, axWindow) } ?? false
                let matchesMainWindow = mainWindow.map { CFEqual($0, axWindow) } ?? false
                let matchesTopmostWindow = topmostAXWindow.map { CFEqual($0, axWindow) } ?? false
                let matchesAccessibilityWindow = mainWindow != nil ? matchesMainWindow : matchesFocusedWindow
                let matchesActiveWindow = topmostAXWindow != nil ? matchesTopmostWindow : matchesAccessibilityWindow
                let focused = pid == frontmostPID && !minimized && (matchesActiveWindow || (topmostAXWindow == nil && mainWindow == nil && focusedWindow == nil && main))
                let runtimeKey = "\(pid)-\(CFHash(axWindow))"
                let stableOrder: Int
                if let existingOrder = windowOrder[runtimeKey] {
                    stableOrder = existingOrder
                } else {
                    stableOrder = nextWindowOrder
                    nextWindowOrder += 1
                    windowOrder[runtimeKey] = stableOrder
                }
                let tabs = finderTabsAsWindows && app.bundleIdentifier == "com.apple.finder"
                    ? finderTabs(in: axWindow) : []
                let entries: [AXUIElement?] = tabs.isEmpty ? [nil] : tabs.map { $0 as AXUIElement? }
                for (tabIndex, tab) in entries.enumerated() {
                    let tabTitle = tab.flatMap { copyAttribute($0, kAXTitleAttribute) as? String }?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let selected = tab.map(isFinderTabSelected) ?? true
                    let itemTitle = tab == nil ? title : tabTitle
                    let model = WindowModel(
                        id: tab.map { "\(runtimeKey)-tab-\(CFHash($0))" } ?? runtimeKey,
                        nativeWindowID: runtimeKey,
                        pid: pid,
                        bundleIdentifier: app.bundleIdentifier,
                        applicationName: applicationName,
                        applicationIcon: app.icon,
                        rawTitle: itemTitle,
                        title: itemTitle.isEmpty ? applicationName : itemTitle,
                        accessibilityRole: role,
                        accessibilitySubrole: subrole,
                        isMinimized: minimized || (app.isHidden && taskbarHiddenPIDs.contains(pid)),
                        isFocused: focused && selected,
                        isMain: main && selected,
                        axWindow: axWindow,
                        finderTab: tab
                    )
                    appWindows.append((stableOrder, tabIndex, model))
                }
            }
            result.append(contentsOf: appWindows.sorted {
                $0.order == $1.order ? $0.tabIndex < $1.tabIndex : $0.order < $1.order
            }.map(\.model))
        }
        return result
    }

    @discardableResult
    func activate(_ window: WindowModel) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: window.pid) else { return false }
        let requestID = UUID()
        activationRequestID = requestID
        if app.isHidden { app.unhide() }
        let axApp = AXUIElementCreateApplication(window.pid)
        let displayableWindows = (copyAttribute(axApp, kAXWindowsAttribute) as? [AXUIElement] ?? [])
            .filter { shouldIncludeWindow($0, bundleIdentifier: window.bundleIdentifier) }
        let currentWindow = currentAXWindow(for: window, among: displayableWindows) ?? window.axWindow
        let needsWindowPromotion = window.finderTab != nil ||
            displayableWindows.count != 1 ||
            !CFEqual(displayableWindows[0], currentWindow)
        let wasMinimized = (copyAttribute(currentWindow, kAXMinimizedAttribute) as? Bool) ?? window.isMinimized
        let restored = wasMinimized
            ? setAttribute(currentWindow, kAXMinimizedAttribute, value: false as CFBoolean) : false
        let alreadyFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == window.pid
        let activatedThroughWorkspace = alreadyFrontmost || app.activate(options: [.activateIgnoringOtherApps])
        let activatedThroughAccessibility = activatedThroughWorkspace
            ? false : setAttribute(axApp, kAXFrontmostAttribute, value: true as CFBoolean)
        // A single document window needs only app activation. AXMain/AXFocused/AXRaise
        // after that can make apps such as ChatGPT briefly redraw the same window.
        let promoted = needsWindowPromotion ? promote(currentWindow) : false
        let selectedTab = selectFinderTab(window.finderTab)

        // Some apps acknowledge activation before switching their selected window.
        // Retry only when the requested window is still not focused; unconditional
        // re-activation can briefly flash another window in a multi-window app.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self, weak app] in
            guard let self, let app, !app.isTerminated,
                  self.activationRequestID == requestID else { return }
            guard needsWindowPromotion,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == window.pid,
                  !self.isCurrentlyFocused(window) else { return }
            _ = self.promote(currentWindow)
            _ = self.selectFinderTab(window.finderTab)
        }

        let activated = restored || activatedThroughWorkspace || activatedThroughAccessibility || promoted || selectedTab
        if activated { recentActivation = (window.id, Date()) }
        return activated
    }

    @discardableResult
    func toggle(_ window: WindowModel) -> Bool {
        let isMinimized = (copyAttribute(window.axWindow, kAXMinimizedAttribute) as? Bool) ?? window.isMinimized
        let wasRecentlyActivated = recentActivation.map {
            $0.windowID == window.id && Date().timeIntervalSince($0.date) < 0.8 &&
                NSWorkspace.shared.frontmostApplication?.processIdentifier == window.pid
        } ?? false
        if !isMinimized && (wasRecentlyActivated || isCurrentlyFocused(window)) {
            activationRequestID = UUID()
            recentActivation = nil
            return setAttribute(window.axWindow, kAXMinimizedAttribute, value: true as CFBoolean)
        }
        return activate(window)
    }

    func isMinimized(_ window: WindowModel) -> Bool {
        guard NSRunningApplication(processIdentifier: window.pid) != nil else { return false }
        let axApp = AXUIElementCreateApplication(window.pid)
        let candidates = copyAttribute(axApp, kAXWindowsAttribute) as? [AXUIElement] ?? []
        let currentWindow = currentAXWindow(for: window, among: candidates) ?? window.axWindow
        return hasMinimizedEvidence(currentWindow)
    }

    func minimize(_ window: WindowModel) -> Bool {
        guard NSRunningApplication(processIdentifier: window.pid)?.isHidden == false else { return false }
        let axApp = AXUIElementCreateApplication(window.pid)
        let displayableWindows = (copyAttribute(axApp, kAXWindowsAttribute) as? [AXUIElement] ?? [])
            .filter { shouldIncludeWindow($0, bundleIdentifier: window.bundleIdentifier) }
        guard let currentWindow = currentAXWindow(for: window, among: displayableWindows) else { return false }
        return setAttribute(currentWindow, kAXMinimizedAttribute, value: true as CFBoolean)
    }

    func hasOnscreenWindow(for pid: pid_t) -> Bool {
        topmostScreenWindow(for: pid) != nil
    }

    func onscreenApplicationPIDs() -> Set<pid_t> {
        let entries = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] ?? []
        return Set(entries.compactMap { entry in
            guard (entry[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  (entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                  let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds),
                  frame.width > 1, frame.height > 1,
                  let pid = entry[kCGWindowOwnerPID as String] as? NSNumber else { return nil }
            return pid_t(pid.int32Value)
        })
    }

    private func currentAXWindow(for window: WindowModel, among candidates: [AXUIElement]) -> AXUIElement? {
        if let exact = candidates.first(where: { CFEqual($0, window.axWindow) }) { return exact }
        guard !window.rawTitle.isEmpty else { return nil }
        let titleMatches = candidates.filter {
            (copyAttribute($0, kAXTitleAttribute) as? String) == window.rawTitle
        }
        return titleMatches.count == 1 ? titleMatches[0] : nil
    }

    func frame(of window: WindowModel) -> CGRect? {
        guard let positionValue = copyAttribute(window.axWindow, kAXPositionAttribute),
              let sizeValue = copyAttribute(window.axWindow, kAXSizeAttribute),
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size),
              size.width > 0, size.height > 0 else { return nil }
        return CGRect(origin: position, size: size)
    }

    func minimizeAll(_ windows: [WindowModel]) -> [WindowModel] {
        windows.filter { window in
            guard !isMinimized(window),
                  NSRunningApplication(processIdentifier: window.pid)?.isHidden == false else { return false }
            return setAttribute(window.axWindow, kAXMinimizedAttribute, value: true as CFBoolean)
        }
    }

    func restoreMinimized(_ windows: [WindowModel]) {
        for window in windows where isMinimized(window) {
            let axApp = AXUIElementCreateApplication(window.pid)
            let candidates = copyAttribute(axApp, kAXWindowsAttribute) as? [AXUIElement] ?? []
            let currentWindow = currentAXWindow(for: window, among: candidates) ?? window.axWindow
            _ = setAttribute(currentWindow, kAXMinimizedAttribute, value: false as CFBoolean)
        }
    }

    @discardableResult
    func activateApplication(_ app: NSRunningApplication) -> Bool {
        if app.isHidden { app.unhide() }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        let activatedThroughAccessibility = setAttribute(axApp, kAXFrontmostAttribute, value: true as CFBoolean)
        let activatedThroughWorkspace = app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        return activatedThroughAccessibility || activatedThroughWorkspace
    }

    @discardableResult
    func reopenApplication(_ app: NSRunningApplication) -> Bool {
        let activated = activateApplication(app)
        let target = NSAppleEventDescriptor(processIdentifier: app.processIdentifier)
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEReopenApplication),
            targetDescriptor: target,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        do {
            _ = try event.sendEvent(options: [.noReply], timeout: 1)
        } catch {
            let applicationName = app.localizedName ?? "Unknown App"
            logger.error("Unable to send reopen event to \(applicationName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return activated
        }
        return true
    }

    func updateWindowSpaceReservations(
        for windows: [WindowModel],
        panelFrame: CGRect,
        screenFrame: CGRect,
        visibleFrame: CGRect,
        clearance: CGFloat = WindowSpaceReservationGeometry.panelClearance,
        enabled: Bool
    ) {
        guard enabled else {
            clearWindowSpaceReservations(restore: true, windows: windows)
            return
        }

        let activeWindowIDs = Set(windows.map(\.id))
        for (id, reservation) in reservedWindowFrames where !activeWindowIDs.contains(id) {
            activeWindowLifts.removeValue(forKey: id)
            if let currentFrame = windowFrame(reservation.window),
               WindowSpaceReservationGeometry.approximatelyEqual(currentFrame, reservation.applied) {
                _ = setWindowFrame(reservation.window, frame: reservation.original)
            }
            reservedWindowFrames.removeValue(forKey: id)
        }
        liftSuppressedFrames = liftSuppressedFrames.filter { activeWindowIDs.contains($0.key) }

        for window in windows where !window.isMinimized {
            if let pointerFrame = pointerAvoidedFrames[window.nativeWindowID],
               WindowSpaceReservationGeometry.approximatelyEqual(windowFrame(window.axWindow) ?? .zero, pointerFrame.applied) {
                continue
            }
            if (copyAttribute(window.axWindow, "AXFullScreen") as? Bool) == true {
                continue
            }
            guard let currentFrame = windowFrame(window.axWindow) else { continue }
            if activeWindowLifts[window.id] != nil { continue }
            if let suppressedFrame = liftSuppressedFrames[window.id] {
                if WindowSpaceReservationGeometry.approximatelyEqual(currentFrame, suppressedFrame) {
                    continue
                }
                liftSuppressedFrames.removeValue(forKey: window.id)
            }

            var reservation = reservedWindowFrames[window.id]
            if let existing = reservation {
                let stillManaged = WindowSpaceReservationGeometry.approximatelyEqual(currentFrame, existing.applied)
                let systemRestoredOriginal = WindowSpaceReservationGeometry.approximatelyEqual(currentFrame, existing.original)
                if systemRestoredOriginal && !stillManaged {
                    // Some apps immediately restore their own tiled size. Do not fight
                    // them every refresh: that makes the window visibly bounce.
                    liftSuppressedFrames[window.id] = currentFrame
                    reservedWindowFrames.removeValue(forKey: window.id)
                    continue
                }
                if !stillManaged && !systemRestoredOriginal {
                    reservedWindowFrames.removeValue(forKey: window.id)
                    reservation = nil
                }
            }

            let baseline = reservation?.original ?? currentFrame
            guard let adjusted = WindowSpaceReservationGeometry.adjustedFrame(
                for: baseline,
                screenFrame: screenFrame,
                visibleFrame: visibleFrame,
                panelFrame: panelFrame,
                clearance: clearance
            ) else {
                if let existing = reservation,
                   WindowSpaceReservationGeometry.approximatelyEqual(currentFrame, existing.applied) {
                    _ = setWindowFrame(window.axWindow, frame: existing.original)
                }
                reservedWindowFrames.removeValue(forKey: window.id)
                continue
            }

            if WindowSpaceReservationGeometry.approximatelyEqual(currentFrame, adjusted) {
                reservedWindowFrames[window.id] = ReservedWindowFrame(
                    window: window.axWindow,
                    original: baseline,
                    applied: adjusted
                )
                continue
            }
            beginWindowLift(id: window.id, window: window.axWindow,
                            original: baseline, start: currentFrame, target: adjusted)
        }
    }

    func moveWindowsAboveTaskbar(_ windows: [WindowModel], panelFrame: CGRect,
                                screenFrame: CGRect, visibleFrame: CGRect, desktopTop: CGFloat,
                                includeOrdinaryWindows: Bool) {
        guard let entries = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return }
        let activeIDs = Set(windows.map(\.nativeWindowID))
        pointerAvoidedFrames = pointerAvoidedFrames.filter { activeIDs.contains($0.key) }
        pointerSuppressedFrames = pointerSuppressedFrames.filter { activeIDs.contains($0.key) }
        pointerSuppressedAt = pointerSuppressedAt.filter { activeIDs.contains($0.key) }
        pointerDefaultRetries = pointerDefaultRetries.filter { activeIDs.contains($0.key) }
        pointerCandidateFrames = pointerCandidateFrames.filter { activeIDs.contains($0.key) }
        pointerDefaultLayoutFrames = pointerDefaultLayoutFrames.filter { activeIDs.contains($0.key) }
        activePointerRetractions = activePointerRetractions.filter { activeIDs.contains($0.key) }
        var seen = Set<CFHashCode>()
        for window in windows where !window.isMinimized {
            guard seen.insert(CFHash(window.axWindow)).inserted,
                  (window.accessibilitySubrole == kAXStandardWindowSubrole || (window.accessibilitySubrole ?? "").isEmpty),
                  NSRunningApplication(processIdentifier: window.pid)?.isHidden == false,
                  (copyAttribute(window.axWindow, "AXFullScreen") as? Bool) != true,
                  !reservedWindowFrames.values.contains(where: { CFEqual($0.window, window.axWindow) }),
                  let current = windowFrame(window.axWindow) else { continue }
            if activePointerRetractions[window.nativeWindowID] != nil { continue }
            let detectedDefault = PointerWindowAvoidanceGeometry.isDefaultAvoidanceWindow(
                current, screen: screenFrame, visibleScreen: visibleFrame, desktopTop: desktopTop)
            let rememberedDefault = pointerDefaultLayoutFrames[window.nativeWindowID].map { original in
                guard let target = PointerWindowAvoidanceGeometry.adjustedFrame(window: original,
                    screen: screenFrame, visibleScreen: visibleFrame, panel: panelFrame,
                    desktopTop: desktopTop) else { return false }
                return PointerWindowAvoidanceGeometry.isOnAnimationPath(current, from: original, to: target)
            } ?? false
            let defaultLayout = detectedDefault || rememberedDefault
            if detectedDefault && !rememberedDefault { pointerDefaultLayoutFrames[window.nativeWindowID] = current }
            if !defaultLayout { pointerDefaultLayoutFrames.removeValue(forKey: window.nativeWindowID) }
            if let prior = pointerAvoidedFrames[window.nativeWindowID],
               !WindowSpaceReservationGeometry.approximatelyEqual(current, prior.applied) {
                pointerAvoidedFrames.removeValue(forKey: window.nativeWindowID)
                if WindowSpaceReservationGeometry.approximatelyEqual(current, prior.original) {
                    // An immediate rebound is an app rejecting our adjustment. A later
                    // maximize/tile action must be eligible for its default animation again.
                    if !defaultLayout || Date().timeIntervalSince(prior.lastAdjustmentAt) < 1.5 {
                        suppressPointerAvoidance(window.nativeWindowID, frame: current)
                    }
                }
            }
            if let suppressed = pointerSuppressedFrames[window.nativeWindowID] {
                let id = window.nativeWindowID
                if WindowSpaceReservationGeometry.approximatelyEqual(current, suppressed) {
                    guard PointerWindowAvoidanceGeometry.canRetryDefaultLayout(isDefault: defaultLayout,
                        elapsed: Date().timeIntervalSince(pointerSuppressedAt[id] ?? Date()),
                        retries: pointerDefaultRetries[id] ?? 0) else { continue }
                    pointerDefaultRetries[id, default: 0] += 1
                } else {
                    pointerDefaultRetries.removeValue(forKey: id)
                }
                pointerSuppressedFrames.removeValue(forKey: id)
                pointerSuppressedAt.removeValue(forKey: id)
            }
            guard includeOrdinaryWindows || defaultLayout else { continue }
            // A maximize/tile transition can span several AX observations. Wait for
            // a stable frame before starting our own animation.
            if let candidate = pointerCandidateFrames[window.nativeWindowID],
               WindowSpaceReservationGeometry.approximatelyEqual(current, candidate.frame, tolerance: 2) {
                let delay = defaultLayout ? PointerWindowAvoidanceSettings.tiledDelay : 0
                guard Date().timeIntervalSince(candidate.since) >= 0.2 + delay else { continue }
            } else {
                pointerCandidateFrames[window.nativeWindowID] = (current, Date())
                continue
            }
            guard let target = PointerWindowAvoidanceGeometry.adjustedFrame(window: current,
                screen: screenFrame, visibleScreen: visibleFrame, panel: panelFrame, desktopTop: desktopTop) else { continue }
            // AX is already bound to this window. An on-screen PID/frame
            // match is sufficient; the title matcher uses a stricter 2pt tolerance
            // and can reject valid windows whose CG/AX bounds differ slightly.
            let isOnScreen = entries.contains { entry in
                guard (entry[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                      (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == window.pid,
                      (entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                      let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
                      let frame = CGRect(dictionaryRepresentation: bounds) else { return false }
                return WindowSpaceReservationGeometry.approximatelyEqual(frame, current, tolerance: 6)
            }
            guard isOnScreen else { continue }
            let attribute = target.size == current.size ? kAXPositionAttribute : kAXSizeAttribute
            var settable: DarwinBoolean = false
            guard AXUIElementIsAttributeSettable(window.axWindow, attribute as CFString,
                &settable) == .success, settable.boolValue else { continue }
            let id = window.nativeWindowID
            let token = UUID()
            let original = pointerAvoidedFrames[id]?.original ?? current
            let animationDuration = PointerWindowAvoidanceSettings.animationDuration
            pointerAvoidedFrames[id] = ReservedWindowFrame(window: window.axWindow,
                original: original, applied: current)
            activePointerRetractions[id] = token
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60.0) { [weak self] in
                // Begin when the initial window scan has yielded the main thread.
                // Counting that scan as animation time would jump over the opening frames.
                let startedAt = ProcessInfo.processInfo.systemUptime - 1.0 / 60.0
                self?.advancePointerRetraction(id: id, token: token, start: current,
                    target: target, startedAt: startedAt, duration: animationDuration)
            }
        }
    }

    private func advancePointerRetraction(id: String, token: UUID,
                                           start: CGRect, target: CGRect, startedAt: TimeInterval,
                                           duration: TimeInterval) {
        guard activePointerRetractions[id] == token else { return }
        guard var reservation = pointerAvoidedFrames[id],
              let current = windowFrame(reservation.window) else {
            activePointerRetractions.removeValue(forKey: id)
            return
        }
        guard NSEvent.pressedMouseButtons == 0,
              PointerWindowAvoidanceGeometry.isOnAnimationPath(current, from: start, to: target) else {
            activePointerRetractions.removeValue(forKey: id)
            suppressPointerAvoidance(id, frame: current)
            return
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
        let progress = PointerWindowAvoidanceGeometry.animationProgress(elapsed: elapsed, duration: duration)
        let next = PointerWindowAvoidanceGeometry.animationFrame(
            from: start, to: target, progress: progress)
        let updated: Bool
        if start.size == target.size {
            var position = next.origin
            if let value = AXValueCreate(.cgPoint, &position) {
                updated = setAttribute(reservation.window, kAXPositionAttribute, value: value)
            } else { updated = false }
        } else {
            var size = next.size
            if let value = AXValueCreate(.cgSize, &size) {
                updated = setAttribute(reservation.window, kAXSizeAttribute, value: value)
            } else { updated = false }
        }
        guard updated, let applied = windowFrame(reservation.window) else {
            activePointerRetractions.removeValue(forKey: id)
            suppressPointerAvoidance(id, frame: windowFrame(reservation.window) ?? current)
            return
        }
        reservation.applied = applied
        reservation.lastAdjustmentAt = Date()
        pointerAvoidedFrames[id] = reservation
        guard PointerWindowAvoidanceGeometry.isOnAnimationPath(applied, from: start, to: target) else {
            activePointerRetractions.removeValue(forKey: id)
            suppressPointerAvoidance(id, frame: applied)
            return
        }
        if progress >= 1 {
            if WindowSpaceReservationGeometry.approximatelyEqual(applied, target, tolerance: 2) {
                activePointerRetractions.removeValue(forKey: id)
                return
            }
            // Give the app a bounded settling period rather than treating one
            // delayed AX read as a permanent refusal to resize.
            if elapsed >= duration + 0.35 {
                activePointerRetractions.removeValue(forKey: id)
                suppressPointerAvoidance(id, frame: applied)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
                self?.advancePointerRetraction(id: id, token: token, start: start,
                    target: target, startedAt: startedAt, duration: duration)
            }
            return
        }
        // AX round trips consume time. Schedule against the original clock instead
        // of adding a full delay after each reply; skip stale frames when an app is slow.
        let nowElapsed = ProcessInfo.processInfo.systemUptime - startedAt
        let delay = PointerWindowAvoidanceGeometry.nextAnimationDelay(elapsed: nowElapsed, duration: duration)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.advancePointerRetraction(id: id, token: token, start: start,
                target: target, startedAt: startedAt, duration: duration)
        }
    }

    private func beginWindowLift(id: String, window: AXUIElement,
                                 original: CGRect, start: CGRect, target: CGRect) {
        let token = UUID()
        activeWindowLifts[id] = token
        reservedWindowFrames[id] = ReservedWindowFrame(window: window, original: original, applied: start)
        advanceWindowLift(id: id, token: token, start: start, target: target, step: 1)
    }

    private func advanceWindowLift(id: String, token: UUID,
                                   start: CGRect, target: CGRect, step: Int) {
        guard activeWindowLifts[id] == token,
              var reservation = reservedWindowFrames[id],
              let current = windowFrame(reservation.window) else {
            activeWindowLifts.removeValue(forKey: id)
            return
        }
        guard WindowSpaceReservationGeometry.approximatelyEqual(current, reservation.applied, tolerance: 6) else {
            // The user or the app moved the window during the animation.
            activeWindowLifts.removeValue(forKey: id)
            liftSuppressedFrames[id] = current
            reservedWindowFrames.removeValue(forKey: id)
            return
        }
        let steps = 6
        let next = WindowSpaceReservationGeometry.liftFrame(
            from: start, to: target, progress: CGFloat(step) / CGFloat(steps)
        )
        guard setWindowFrame(reservation.window, frame: next) else {
            activeWindowLifts.removeValue(forKey: id)
            reservedWindowFrames.removeValue(forKey: id)
            liftSuppressedFrames[id] = current
            return
        }
        reservation.applied = windowFrame(reservation.window) ?? next
        reservedWindowFrames[id] = reservation
        if step == steps {
            activeWindowLifts.removeValue(forKey: id)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            self?.advanceWindowLift(id: id, token: token, start: start, target: target, step: step + 1)
        }
    }

    func clearWindowSpaceReservations(restore: Bool, windows _: [WindowModel]) {
        activeWindowLifts.removeAll()
        liftSuppressedFrames.removeAll()
        if restore {
            for reservation in reservedWindowFrames.values {
                guard let currentFrame = windowFrame(reservation.window),
                      WindowSpaceReservationGeometry.approximatelyEqual(currentFrame, reservation.applied) else { continue }
                _ = setWindowFrame(reservation.window, frame: reservation.original)
            }
        }
        reservedWindowFrames.removeAll()
        clearPointerWindowAvoidance(restore: restore)
    }

    func clearPointerWindowAvoidance(restore: Bool) {
        activePointerRetractions.removeAll()
        if restore {
            for prior in pointerAvoidedFrames.values {
                guard let current = windowFrame(prior.window),
                      WindowSpaceReservationGeometry.approximatelyEqual(current, prior.applied) else { continue }
                _ = setWindowFrame(prior.window, frame: prior.original)
            }
        }
        pointerAvoidedFrames.removeAll()
        pointerSuppressedFrames.removeAll()
        pointerSuppressedAt.removeAll()
        pointerDefaultRetries.removeAll()
        pointerCandidateFrames.removeAll()
        pointerDefaultLayoutFrames.removeAll()
    }

    func showAllWindows(for pid: pid_t, from windows: [WindowModel]) {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        _ = app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        for window in windows where window.pid == pid {
            if window.isMinimized { setAttribute(window.axWindow, kAXMinimizedAttribute, value: false as CFBoolean) }
            _ = performAction(window.axWindow, kAXRaiseAction)
        }
    }

    @discardableResult
    func close(_ window: WindowModel) -> Bool {
        if let tab = window.finderTab {
            guard let children = copyAttribute(tab, kAXChildrenAttribute) as? [AXUIElement],
                  let closeButton = children.first(where: {
                      (copyAttribute($0, kAXRoleAttribute) as? String) == kAXButtonRole
                  }) else { return false }
            return performAction(closeButton, kAXPressAction)
        }
        return performAction(window.axWindow, "AXClose")
    }

    func isCurrentlyFocused(_ window: WindowModel) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == window.pid else { return false }
        if let tab = window.finderTab, !isFinderTabSelected(tab) { return false }
        let axApp = AXUIElementCreateApplication(window.pid)
        if let values = copyAttribute(axApp, kAXWindowsAttribute) as? [AXUIElement],
           let topmostWindow = topmostScreenWindow(for: window.pid),
           let resolvedWindow = matchingWindow(for: topmostWindow, among: values.filter {
               shouldIncludeWindow($0, bundleIdentifier: window.bundleIdentifier)
           }) {
            return CFEqual(resolvedWindow, window.axWindow)
        }
        if let mainWindow = copyAttribute(axApp, kAXMainWindowAttribute),
           CFEqual(mainWindow, window.axWindow) { return true }
        if let focusedWindow = copyAttribute(axApp, kAXFocusedWindowAttribute) {
            return CFEqual(focusedWindow, window.axWindow)
        }
        return window.isMain
    }

    private func topmostScreenWindow(for targetPID: pid_t) -> ScreenWindow? {
        guard let entries = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        for entry in entries {
            guard (entry[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let pidNumber = entry[kCGWindowOwnerPID as String] as? NSNumber else { continue }
            let pid = pid_t(pidNumber.int32Value)
            guard pid == targetPID else { continue }
            if let alpha = entry[kCGWindowAlpha as String] as? NSNumber, alpha.doubleValue <= 0 { continue }
            guard let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds),
                  frame.width > 1, frame.height > 1 else { continue }
            return ScreenWindow(
                pid: pid,
                frame: frame,
                title: entry[kCGWindowName as String] as? String ?? ""
            )
        }
        return nil
    }

    private func matchingWindow(for screenWindow: ScreenWindow, among windows: [AXUIElement]) -> AXUIElement? {
        let screenTitle = screenWindow.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !screenTitle.isEmpty {
            let titleMatches = windows.filter { axWindow in
                guard let rawTitle = copyAttribute(axWindow, kAXTitleAttribute) as? String else { return false }
                let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { return false }
                return title == screenTitle || title.contains(screenTitle) || screenTitle.contains(title)
            }
            if titleMatches.count == 1 { return titleMatches[0] }
        }

        // Several browser windows are commonly maximized to the exact same
        // frame. A frame match is safe only when it identifies one window.
        let frameMatches = windows.filter { axWindow in
            guard let frame = windowFrame(axWindow) else { return false }
            let tolerance: CGFloat = 2
            return abs(frame.minX - screenWindow.frame.minX) <= tolerance &&
                abs(frame.minY - screenWindow.frame.minY) <= tolerance &&
                abs(frame.width - screenWindow.frame.width) <= tolerance &&
                abs(frame.height - screenWindow.frame.height) <= tolerance
        }
        return frameMatches.count == 1 ? frameMatches[0] : nil
    }

    @discardableResult
    private func promote(_ window: AXUIElement) -> Bool {
        if (copyAttribute(window, kAXMinimizedAttribute) as? Bool) == true {
            _ = setAttribute(window, kAXMinimizedAttribute, value: false as CFBoolean)
        }
        let madeMain = setAttribute(window, kAXMainAttribute, value: true as CFBoolean)
        let focused = setAttribute(window, kAXFocusedAttribute, value: true as CFBoolean)
        let raised = performAction(window, kAXRaiseAction)
        return madeMain || focused || raised
    }

    private func windowFrame(_ window: AXUIElement) -> CGRect? {
        guard let positionValue = copyAttribute(window, kAXPositionAttribute),
              let sizeValue = copyAttribute(window, kAXSizeAttribute),
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }

    private func setWindowFrame(_ window: AXUIElement, frame: CGRect) -> Bool {
        let currentFrame = windowFrame(window)
        var position = frame.origin
        var size = frame.size
        guard let positionValue = AXValueCreate(.cgPoint, &position),
              let sizeValue = AXValueCreate(.cgSize, &size) else { return false }
        let moved = currentFrame.map {
            abs($0.minX - frame.minX) <= 1 && abs($0.minY - frame.minY) <= 1
        } ?? false || setAttribute(window, kAXPositionAttribute, value: positionValue)
        let resized = currentFrame.map {
            abs($0.width - frame.width) <= 1 && abs($0.height - frame.height) <= 1
        } ?? false || setAttribute(window, kAXSizeAttribute, value: sizeValue)
        return moved && resized
    }

    private func shouldIgnoreWindow(bundleIdentifier: String?, title: String) -> Bool {
        guard let bundleIdentifier,
              let ignoredTitles = ignoredWindowTitles[bundleIdentifier] else { return false }
        return ignoredTitles.contains(title.lowercased())
    }

    private func finderTabs(in window: AXUIElement) -> [AXUIElement] {
        func tabGroup(in element: AXUIElement, depth: Int) -> AXUIElement? {
            if (copyAttribute(element, kAXRoleAttribute) as? String) == "AXTabGroup" {
                return element
            }
            guard depth > 0,
                  let children = copyAttribute(element, kAXChildrenAttribute) as? [AXUIElement] else {
                return nil
            }
            for child in children {
                if let group = tabGroup(in: child, depth: depth - 1) { return group }
            }
            return nil
        }

        guard let group = tabGroup(in: window, depth: 4),
              let children = copyAttribute(group, kAXChildrenAttribute) as? [AXUIElement] else {
            return []
        }
        return children.filter { child in
            let role = copyAttribute(child, kAXRoleAttribute) as? String
            let title = copyAttribute(child, kAXTitleAttribute) as? String
            return (role == "AXRadioButton" || role == "AXTab") && !(title?.isEmpty ?? true)
        }
    }

    private func isFinderTabSelected(_ tab: AXUIElement) -> Bool {
        (copyAttribute(tab, kAXValueAttribute) as? Bool) == true
    }

    @discardableResult
    private func selectFinderTab(_ tab: AXUIElement?) -> Bool {
        guard let tab else { return false }
        if isFinderTabSelected(tab) { return true }
        return performAction(tab, kAXPressAction)
    }

    private func shouldIncludeWindow(
        _ window: AXUIElement,
        bundleIdentifier: String?,
        appKey: String? = nil,
        blockedWindowRules: [BlockedWindowRule] = []
    ) -> Bool {
        let title = (copyAttribute(window, kAXTitleAttribute) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if shouldIgnoreWindow(bundleIdentifier: bundleIdentifier, title: title) { return false }

        guard let role = copyAttribute(window, kAXRoleAttribute) as? String,
              role == kAXWindowRole else {
            // Sheets are exposed as AXSheet and must stay attached to their document window.
            return false
        }
        let subrole = copyAttribute(window, kAXSubroleAttribute) as? String
        if let appKey,
           blockedWindowRules.contains(where: {
               $0.matches(
                   appKey: appKey,
                   rawTitle: title,
                   accessibilityRole: role,
                   accessibilitySubrole: subrole
               )
           }) {
            return false
        }
        if WindowFilterRules.shouldIgnoreWindow(subrole: subrole) { return false }

        // Finder can change a normal window's accessibility subrole to AXDialog
        // after it is minimized. Keep that minimized document window visible in
        // TaskDock without weakening dialog filtering for Finder's live popups.
        let isMinimized = hasMinimizedEvidence(window)
        let key = evidenceKey(window)
        if let key, windowEvidence[key]?.destroyed == true { return false }
        if subrole == kAXStandardWindowSubrole,
           (copyAttribute(window, kAXModalAttribute) as? Bool) != true, let key {
            windowEvidence[key, default: MinimizedWindowEvidence()].knownDocument = true
        }
        let wasKnownDocument = key.flatMap { windowEvidence[$0]?.knownDocument } ?? false
        if bundleIdentifier == "com.apple.finder",
           WindowFilterRules.shouldIgnoreFinderWindow(
               title: title,
               subrole: subrole,
               isMinimized: isMinimized
           ) {
            return false
        }
        let isModal = (copyAttribute(window, kAXModalAttribute) as? Bool) == true
        if bundleIdentifier == "com.apple.finder" {
            guard !isModal else { return false }
            let wasKnownDocument = knownFinderDocumentWindows.contains { CFEqual($0, window) }
            if subrole == kAXStandardWindowSubrole {
                if !wasKnownDocument { knownFinderDocumentWindows.append(window) }
                return true
            }
            if isMinimized {
                // Finder may expose a second AXDialog record only after minimizing.
                // Keep a dialog only when it is the same previously seen folder window.
                // Bootstrap already minimized folders once on startup; subsequent
                // refreshes must not introduce newly appearing dialog records.
                if !hasEnumeratedFinderWindows && !wasKnownDocument {
                    knownFinderDocumentWindows.append(window)
                    return true
                }
                return wasKnownDocument
            }
        }

        if WindowFilterRules.shouldKeepMinimizedDocumentWindow(
            bundleIdentifier: bundleIdentifier,
            title: title,
            subrole: subrole,
            isMinimized: isMinimized,
            isModal: isModal,
            wasKnownDocument: wasKnownDocument
        ) {
            return true
        }

        if isModal {
            return false
        }

        // Toolbar menus and temporary pickers can report AXWindow with AXUnknown
        // (Excel does this for its Conditional Formatting menu). Only a standard
        // top-level window becomes a task item; minimized document exceptions
        // have already returned above.
        return WindowFilterRules.shouldIncludeNormalWindow(subrole: subrole)
    }

    private func copyAttribute(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        if error != .success { return nil }
        return value as AnyObject?
    }

    @discardableResult
    private func setAttribute(_ element: AXUIElement, _ attribute: String, value: CFTypeRef) -> Bool {
        let error = AXUIElementSetAttributeValue(element, attribute as CFString, value)
        if error != .success { logger.debug("set \(attribute, privacy: .public) failed: \(error.rawValue, privacy: .public)") }
        return error == .success
    }

    private func performAction(_ element: AXUIElement, _ action: String) -> Bool {
        let error = AXUIElementPerformAction(element, action as CFString)
        if error != .success { logger.debug("action \(action, privacy: .public) failed: \(error.rawValue, privacy: .public)") }
        return error == .success
    }
}
