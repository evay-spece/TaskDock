import AppKit
import ApplicationServices

struct WindowProgressCandidate {
    let id: String
    let pid: pid_t
    let bundleIdentifier: String?
    let isFocused: Bool
    let window: AXUIElement
}

final class WindowProgressScanner: @unchecked Sendable {
    private struct Reading {
        let value: Double
        let indicator: AXUIElement
    }

    private struct RetainedIndicator {
        let indicator: AXUIElement
        let targetID: String
    }

    // Used only on TaskbarPanelController's serial progress queue. Some apps remove
    // utility panels from AXWindows when inactive, although their AX elements remain readable.
    private var retainedByPID: [pid_t: [RetainedIndicator]] = [:]

    func clear() {
        retainedByPID.removeAll()
    }

    func scan(_ candidates: [WindowProgressCandidate]) -> [String: Double] {
        var result: [String: Double] = [:]
        let grouped = Dictionary(grouping: candidates, by: \.pid)
        retainedByPID = retainedByPID.filter { grouped[$0.key] != nil }
        for (pid, targets) in grouped {
            let targetIDs = Set(targets.map(\.id))
            if let download = BrowserDownloadProgress.read(bundleIdentifier: targets[0].bundleIdentifier) {
                let target = targets.first(where: \.isFocused) ?? targets[0]
                result[target.id] = download
            }
            let deadline = Date().addingTimeInterval(0.45)
            var retained = (retainedByPID[pid] ?? []).filter { targetIDs.contains($0.targetID) }
            retained.removeAll { item in
                guard Date() < deadline else { return false }
                guard let value = Self.progressValue(in: item.indicator) else { return true }
                result[item.targetID] = max(result[item.targetID] ?? 0, value)
                return false
            }
            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, 0.15)
            let appWindows = (Self.attribute(application, kAXWindowsAttribute) as? [AXUIElement]) ?? []
            let windows = appWindows.isEmpty ? targets.map(\.window) : Array(appWindows.prefix(12))
            for window in windows {
                guard Date() < deadline else { break }
                var remaining = 48
                guard let reading = Self.progress(in: window, depth: 5,
                                                  deadline: deadline, remaining: &remaining) else { continue }
                let target = targets.first(where: { CFEqual($0.window, window) })
                    ?? targets.first(where: \.isFocused) ?? targets[0]
                let existing = retained.first { CFEqual($0.indicator, reading.indicator) }
                let targetID = existing?.targetID ?? target.id
                result[targetID] = max(result[targetID] ?? 0, reading.value)
                if existing == nil, retained.count < 12 {
                    retained.append(RetainedIndicator(indicator: reading.indicator, targetID: targetID))
                }
            }
            retainedByPID[pid] = retained
        }
        return result
    }

    private static func progress(in element: AXUIElement, depth: Int,
                                 deadline: Date, remaining: inout Int) -> Reading? {
        guard remaining > 0, Date() < deadline else { return nil }
        remaining -= 1
        AXUIElementSetMessagingTimeout(element, 0.15)

        if let value = progressValue(in: element) {
            return Reading(value: value, indicator: element)
        }

        guard depth > 0,
              let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else { return nil }
        for child in children {
            if let value = progress(in: child, depth: depth - 1,
                                    deadline: deadline, remaining: &remaining) {
                return value
            }
        }
        return nil
    }

    private static func progressValue(in element: AXUIElement) -> Double? {
        guard (attribute(element, kAXRoleAttribute) as? String) == kAXProgressIndicatorRole,
              let value = attribute(element, kAXValueAttribute) as? NSNumber else { return nil }
        let minimum = (attribute(element, kAXMinValueAttribute) as? NSNumber)?.doubleValue ?? 0
        let maximum = (attribute(element, kAXMaxValueAttribute) as? NSNumber)?.doubleValue
            ?? (value.doubleValue <= 1 ? 1 : 100)
        return WindowProgressValue.normalized(
            value: value.doubleValue, minimum: minimum, maximum: maximum
        )
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else {
            return nil
        }
        return result
    }
}

enum WindowProgressValue {
    static func normalized(value: Double, minimum: Double, maximum: Double) -> Double? {
        guard value.isFinite, minimum.isFinite, maximum.isFinite,
              maximum > minimum, value > minimum, value < maximum else { return nil }
        return min(1, max(0, (value - minimum) / (maximum - minimum)))
    }
}

@MainActor
final class WindowProgressStore: ObservableObject {
    @Published private(set) var values: [String: Double] = [:]

    func update(_ next: [String: Double]) {
        guard values != next else { return }
        values = next
    }
}
