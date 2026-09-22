import AppKit
import ApplicationServices
import Foundation

@main
struct WindowFilterSelfTest {
    static func main() {
        precondition(WindowFilterRules.shouldIgnoreApplication(
            bundleIdentifier: "com.apple.quicklook.QuickLookUIService"
        ))
        precondition(!WindowFilterRules.shouldIgnoreApplication(bundleIdentifier: "com.apple.Preview"))
        precondition(!WindowFilterRules.shouldIgnoreApplication(bundleIdentifier: "com.apple.finder"))
        precondition(!WindowFilterRules.shouldIgnoreApplication(bundleIdentifier: nil))
        precondition(WindowFilterRules.shouldIgnoreWindow(subrole: "Quick Look"))
        precondition(WindowFilterRules.shouldIgnoreWindow(subrole: "AXQuickLook"))
        precondition(!WindowFilterRules.shouldIgnoreWindow(subrole: "AXStandardWindow"))
        precondition(!WindowFilterRules.shouldIgnoreWindow(subrole: nil))

        var foundLiveQuickLook = false
        for app in NSWorkspace.shared.runningApplications where app.bundleIdentifier == "com.apple.finder" {
            let application = AXUIElementCreateApplication(app.processIdentifier)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value) == .success,
                  let windows = value as? [AXUIElement] else { continue }
            for window in windows {
                var subroleValue: CFTypeRef?
                guard AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleValue) == .success,
                      let subrole = subroleValue as? String,
                      subrole == "Quick Look" else { continue }
                precondition(WindowFilterRules.shouldIgnoreWindow(subrole: subrole))
                foundLiveQuickLook = true
            }
        }
        print(foundLiveQuickLook ? "WINDOW_FILTER_OK live-quick-look" : "WINDOW_FILTER_OK static")
    }
}
