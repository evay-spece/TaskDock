import AppKit
import ApplicationServices
import Carbon
import os.log

final class AXWindowService {
    private struct ReservedWindowFrame {
        let window: AXUIElement
        let original: CGRect
        var applied: CGRect
    }

    private struct ScreenWindow {
        let pid: pid_t
        let frame: CGRect
        let title: String
    }

    private let logger = Logger(subsystem: "com.taskdock.app", category: "accessibility")
    private var windowOrder: [String: Int] = [:]
    private var nextWindowOrder = 0
    private var reservedWindowFrames: [String: ReservedWindowFrame] = [:]
    private let ignoredWindowTitles: [String: Set<String>] = [
        "com.openai.codex": ["computer use", "computer use controls"]
    ]

    func enumerateWindows(
        excludingPID: pid_t,
        showHiddenApps: Bool,
        blacklistedAppKeys: Set<String>,
        blockedWindowRules: [BlockedWindowRule]
    ) -> [WindowModel] {
        guard AXIsProcessTrusted() else { return [] }
        var result: [WindowModel] = []
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        let runningApps = NSWorkspace.shared.runningApplications
            .filter {
                $0.processIdentifier != excludingPID &&
                !WindowFilterRules.shouldIgnoreApplication(bundleIdentifier: $0.bundleIdentifier) &&
                $0.activationPolicy == .regular &&
                (showHiddenApps || !$0.isHidden)
            }
            .sorted {
                ($0.launchDate ?? .distantPast) < ($1.launchDate ?? .distantPast)
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
            let topmostAXWindow: AXUIElement? = topmostWindow.flatMap { screenWindow in
                guard screenWindow.pid == pid else { return nil }
                return matchingWindow(for: screenWindow, among: displayableWindows)
            }

            var appWindows: [(order: Int, model: WindowModel)] = []
            for axWindow in displayableWindows {
                let title = (copyAttribute(axWindow, kAXTitleAttribute) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let role = copyAttribute(axWindow, kAXRoleAttribute) as? String ?? ""
                let subrole = copyAttribute(axWindow, kAXSubroleAttribute) as? String

                let main = (copyAttribute(axWindow, kAXMainAttribute) as? Bool) ?? false
                let minimized = (copyAttribute(axWindow, kAXMinimizedAttribute) as? Bool) ?? false
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
                let model = WindowModel(
                    id: runtimeKey,
                    pid: pid,
                    bundleIdentifier: app.bundleIdentifier,
                    applicationName: applicationName,
                    applicationIcon: app.icon,
                    rawTitle: title,
                    title: title.isEmpty ? applicationName : title,
                    accessibilityRole: role,
                    accessibilitySubrole: subrole,
                    isMinimized: minimized,
                    isFocused: focused,
                    isMain: main,
                    axWindow: axWindow
                )
                appWindows.append((stableOrder, model))
            }
            result.append(contentsOf: appWindows.sorted { $0.order < $1.order }.map(\.model))
        }
        return result
    }

    @discardableResult
    func activate(_ window: WindowModel) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: window.pid) else { return false }
        if app.isHidden { app.unhide() }
        let axApp = AXUIElementCreateApplication(window.pid)
        let activatedThroughWorkspace = app.activate(options: [.activateIgnoringOtherApps])
        let activatedThroughAccessibility = setAttribute(axApp, kAXFrontmostAttribute, value: true as CFBoolean)
        let promoted = promote(window.axWindow)

        // Chromium-based apps can acknowledge activation before their selected
        // native window has changed. Repeat the targeted promotion after that
        // short hand-off without activating every window in the application.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self, weak app] in
            guard let self, let app, !app.isTerminated else { return }
            _ = app.activate(options: [.activateIgnoringOtherApps])
            _ = self.setAttribute(axApp, kAXFrontmostAttribute, value: true as CFBoolean)
            _ = self.promote(window.axWindow)
        }

        return activatedThroughWorkspace || activatedThroughAccessibility || promoted
    }

    @discardableResult
    func toggle(_ window: WindowModel) -> Bool {
        if isCurrentlyFocused(window) {
            setAttribute(window.axWindow, kAXMinimizedAttribute, value: true as CFBoolean)
            return true
        }
        return activate(window)
    }

    func minimizeAll(_ windows: [WindowModel]) {
        for window in windows where !window.isMinimized {
            setAttribute(window.axWindow, kAXMinimizedAttribute, value: true as CFBoolean)
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
        enabled: Bool
    ) {
        guard enabled else {
            clearWindowSpaceReservations(restore: true, windows: windows)
            return
        }

        let activeWindowIDs = Set(windows.map(\.id))
        for (id, reservation) in reservedWindowFrames where !activeWindowIDs.contains(id) {
            if let currentFrame = windowFrame(reservation.window),
               WindowSpaceReservationGeometry.approximatelyEqual(currentFrame, reservation.applied) {
                _ = setWindowFrame(reservation.window, frame: reservation.original)
            }
            reservedWindowFrames.removeValue(forKey: id)
        }

        for window in windows where !window.isMinimized {
            if (copyAttribute(window.axWindow, "AXFullScreen") as? Bool) == true {
                continue
            }
            guard let currentFrame = windowFrame(window.axWindow) else { continue }

            var reservation = reservedWindowFrames[window.id]
            if let existing = reservation {
                let stillManaged = WindowSpaceReservationGeometry.approximatelyEqual(currentFrame, existing.applied)
                let systemRestoredOriginal = WindowSpaceReservationGeometry.approximatelyEqual(currentFrame, existing.original)
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
                panelFrame: panelFrame
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
            if setWindowFrame(window.axWindow, frame: adjusted) {
                reservedWindowFrames[window.id] = ReservedWindowFrame(
                    window: window.axWindow,
                    original: baseline,
                    applied: adjusted
                )
            }
        }
    }

    func clearWindowSpaceReservations(restore: Bool, windows _: [WindowModel]) {
        if restore {
            for reservation in reservedWindowFrames.values {
                guard let currentFrame = windowFrame(reservation.window),
                      WindowSpaceReservationGeometry.approximatelyEqual(currentFrame, reservation.applied) else { continue }
                _ = setWindowFrame(reservation.window, frame: reservation.original)
            }
        }
        reservedWindowFrames.removeAll()
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
        performAction(window.axWindow, "AXClose")
    }

    private func isCurrentlyFocused(_ window: WindowModel) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == window.pid else { return false }
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
        // TaskDock without weakening dialog filtering for Finder's live popups or
        // for any other application.
        let isMinimized = (copyAttribute(window, kAXMinimizedAttribute) as? Bool) ?? false
        if bundleIdentifier == "com.apple.finder",
           WindowFilterRules.shouldIgnoreFinderWindow(
               title: title,
               subrole: subrole,
               isMinimized: isMinimized
           ) {
            return false
        }
        if bundleIdentifier == "com.apple.finder", isMinimized {
            return true
        }

        if (copyAttribute(window, kAXModalAttribute) as? Bool) == true {
            return false
        }

        let transientSubroles: Set<String> = [
            kAXDialogSubrole,
            kAXSystemDialogSubrole,
            kAXFloatingWindowSubrole
        ]
        return subrole.map { !transientSubroles.contains($0) } ?? true
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
