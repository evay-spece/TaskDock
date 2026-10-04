import AppKit
import ApplicationServices

@main
struct FinderTabsSelfTest {
    static func main() {
        guard AXIsProcessTrusted(),
              let finder = NSWorkspace.shared.runningApplications.first(where: {
                  $0.bundleIdentifier == "com.apple.finder"
              }) else {
            print("FINDER_TABS_UNAVAILABLE")
            return
        }
        let app = AXUIElementCreateApplication(finder.processIdentifier)
        let windows = children(of: app, attribute: kAXWindowsAttribute)
        let groups = windows.compactMap { findTabGroup(in: $0, depth: 4) }
        let tabs = groups.map { group in
            children(of: group, attribute: kAXChildrenAttribute).filter { child in
                let role = attribute(child, kAXRoleAttribute) as? String
                let title = attribute(child, kAXTitleAttribute) as? String
                return (role == "AXRadioButton" || role == "AXTab") && !(title?.isEmpty ?? true)
            }
        }
        let counts = tabs.map(\.count)
        let roles = tabs.flatMap { $0 }.compactMap { attribute($0, kAXRoleAttribute) as? String }
        print("FINDER_TAB_COUNTS \(counts) ROLES \(roles)")
        if let multiTabWindow = tabs.first(where: { $0.count >= 2 }) {
            let selected = multiTabWindow.map {
                (attribute($0, kAXValueAttribute) as? Bool) == true
            }
            precondition(selected.filter { $0 }.count == 1, "Expected one selected tab: \(selected)")
            let firstHashes = multiTabWindow.map(CFHash)
            let rereadTabs = children(of: app, attribute: kAXWindowsAttribute)
                .compactMap { findTabGroup(in: $0, depth: 4) }
                .map { children(of: $0, attribute: kAXChildrenAttribute) }
                .first(where: { $0.count >= 2 }) ?? []
            let secondHashes = rereadTabs.filter {
                (attribute($0, kAXRoleAttribute) as? String) == "AXRadioButton"
            }.map(CFHash)
            precondition(firstHashes == secondHashes, "Finder tab identities changed between reads")
            print("FINDER_TABS_SELECTED_STATE_OK")
        }
    }

    private static func findTabGroup(in element: AXUIElement, depth: Int) -> AXUIElement? {
        if (attribute(element, kAXRoleAttribute) as? String) == "AXTabGroup" { return element }
        guard depth > 0 else { return nil }
        for child in children(of: element, attribute: kAXChildrenAttribute) {
            if let group = findTabGroup(in: child, depth: depth - 1) { return group }
        }
        return nil
    }

    private static func children(of element: AXUIElement, attribute name: String) -> [AXUIElement] {
        attribute(element, name) as? [AXUIElement] ?? []
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value as AnyObject?
    }
}
