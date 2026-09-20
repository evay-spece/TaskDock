import AppKit
import ApplicationServices
import os.log

final class AXWindowService {
    private let logger = Logger(subsystem: "com.taskdock.app", category: "accessibility")
    private var windowOrder: [String: Int] = [:]
    private var nextWindowOrder = 0

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

        for app in runningApps {
            let pid = app.processIdentifier
            let applicationName = app.localizedName ?? "Unknown App"
            let appKey = app.bundleIdentifier.map { $0 } ?? "name:\(applicationName)"
            if blacklistedAppKeys.contains(appKey) { continue }
            let axApp = AXUIElementCreateApplication(pid)
            guard let values = copyAttribute(axApp, kAXWindowsAttribute) as? [AXUIElement] else { continue }
            let focusedWindow = copyAttribute(axApp, kAXFocusedWindowAttribute)

            var appWindows: [(order: Int, model: WindowModel)] = []
            for axWindow in values {
                let title = (copyAttribute(axWindow, kAXTitleAttribute) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let role = copyAttribute(axWindow, kAXRoleAttribute) as? String
                let subrole = copyAttribute(axWindow, kAXSubroleAttribute) as? String
                if role != kAXWindowRole && subrole != kAXStandardWindowSubrole && title.isEmpty { continue }

                let minimized = (copyAttribute(axWindow, kAXMinimizedAttribute) as? Bool) ?? false
                let focused = pid == frontmostPID && (focusedWindow.map { CFEqual($0, axWindow) } ?? false)
                let main = (copyAttribute(axWindow, kAXMainAttribute) as? Bool) ?? false
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
        _ = app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        let raised = performAction(window.axWindow, kAXRaiseAction)
        if !raised { setAttribute(window.axWindow, kAXMainAttribute, value: true as CFBoolean) }
        if !raised { setAttribute(window.axWindow, kAXFocusedAttribute, value: true as CFBoolean) }
        return raised
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

    private func copyAttribute(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        if error != .success { return nil }
        return value as AnyObject?
    }

    private func setAttribute(_ element: AXUIElement, _ attribute: String, value: CFTypeRef) {
        let error = AXUIElementSetAttributeValue(element, attribute as CFString, value)
        if error != .success { logger.debug("set \(attribute, privacy: .public) failed: \(error.rawValue, privacy: .public)") }
    }

    private func performAction(_ element: AXUIElement, _ action: String) -> Bool {
        let error = AXUIElementPerformAction(element, action as CFString)
        if error != .success { logger.debug("action \(action, privacy: .public) failed: \(error.rawValue, privacy: .public)") }
        return error == .success
    }
}
