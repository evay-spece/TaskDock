import AppKit
import ApplicationServices
import os.log

final class AXWindowService {
    private struct ScreenWindow {
        let pid: pid_t
        let frame: CGRect
        let title: String
    }

    private let logger = Logger(subsystem: "com.taskdock.app", category: "accessibility")
    private var windowOrder: [String: Int] = [:]
    private var nextWindowOrder = 0
    private let ignoredWindowTitles: [String: Set<String>] = [
        "com.openai.codex": ["computer use", "computer use controls"]
    ]

    func enumerateWindows(excludingPID: pid_t, showHiddenApps: Bool, blacklistedAppKeys: Set<String>) -> [WindowModel] {
        guard AXIsProcessTrusted() else { return [] }
        var result: [WindowModel] = []
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        let runningApps = NSWorkspace.shared.runningApplications
            .filter {
                $0.processIdentifier != excludingPID &&
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
            let topmostAXWindow: AXUIElement? = topmostWindow.flatMap { screenWindow in
                guard screenWindow.pid == pid else { return nil }
                return values.first { matches($0, screenWindow: screenWindow) }
            }

            var appWindows: [(order: Int, model: WindowModel)] = []
            for axWindow in values {
                let title = (copyAttribute(axWindow, kAXTitleAttribute) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if shouldIgnoreWindow(bundleIdentifier: app.bundleIdentifier, title: title) { continue }
                let role = copyAttribute(axWindow, kAXRoleAttribute) as? String
                let subrole = copyAttribute(axWindow, kAXSubroleAttribute) as? String
                if role != kAXWindowRole && subrole != kAXStandardWindowSubrole && title.isEmpty { continue }

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
                    title: title.isEmpty ? applicationName : title,
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
        if window.isMinimized { setAttribute(window.axWindow, kAXMinimizedAttribute, value: false as CFBoolean) }
        if app.isHidden { app.unhide() }
        let axApp = AXUIElementCreateApplication(window.pid)
        setAttribute(window.axWindow, kAXMainAttribute, value: true as CFBoolean)
        setAttribute(window.axWindow, kAXFocusedAttribute, value: true as CFBoolean)
        let activatedThroughAccessibility = setAttribute(axApp, kAXFrontmostAttribute, value: true as CFBoolean)
        if !activatedThroughAccessibility {
            _ = app.activate(options: [.activateIgnoringOtherApps])
        }
        let raised = performAction(window.axWindow, kAXRaiseAction)
        return activatedThroughAccessibility || raised
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
        if let topmostWindow = topmostScreenWindow(for: window.pid) {
            if matches(window.axWindow, screenWindow: topmostWindow) { return true }
        }
        let axApp = AXUIElementCreateApplication(window.pid)
        if let mainWindow = copyAttribute(axApp, kAXMainWindowAttribute) {
            return CFEqual(mainWindow, window.axWindow)
        }
        guard let focusedWindow = copyAttribute(axApp, kAXFocusedWindowAttribute) else { return window.isMain }
        return CFEqual(focusedWindow, window.axWindow)
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

    private func matches(_ axWindow: AXUIElement, screenWindow: ScreenWindow) -> Bool {
        if let frame = windowFrame(axWindow) {
            let tolerance: CGFloat = 2
            if abs(frame.minX - screenWindow.frame.minX) <= tolerance,
               abs(frame.minY - screenWindow.frame.minY) <= tolerance,
               abs(frame.width - screenWindow.frame.width) <= tolerance,
               abs(frame.height - screenWindow.frame.height) <= tolerance {
                return true
            }
        }

        guard !screenWindow.title.isEmpty,
              let title = copyAttribute(axWindow, kAXTitleAttribute) as? String else { return false }
        return title == screenWindow.title || title.contains(screenWindow.title) || screenWindow.title.contains(title)
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

    private func shouldIgnoreWindow(bundleIdentifier: String?, title: String) -> Bool {
        guard let bundleIdentifier,
              let ignoredTitles = ignoredWindowTitles[bundleIdentifier] else { return false }
        return ignoredTitles.contains(title.lowercased())
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
