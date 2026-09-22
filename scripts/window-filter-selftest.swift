import AppKit
import ApplicationServices
import Foundation

@main
struct WindowFilterSelfTest {
    static func main() {
        precondition(WindowFilterRules.shouldIgnoreApplication(
            bundleIdentifier: "com.apple.quicklook.QuickLookUIService"
        ))
        precondition(WindowFilterRules.shouldIgnoreApplication(
            bundleIdentifier: "com.aodaren.inputmethod.Qingg"
        ))
        precondition(WindowFilterRules.shouldIgnoreApplication(
            bundleIdentifier: "com.apple.inputmethod.SCIM"
        ))
        precondition(WindowFilterRules.shouldIgnoreApplication(
            bundleIdentifier: "com.apple.TextInputUI.xpc.CursorUIViewService"
        ))
        precondition(!WindowFilterRules.shouldIgnoreApplication(bundleIdentifier: "com.apple.Preview"))
        precondition(!WindowFilterRules.shouldIgnoreApplication(bundleIdentifier: "com.apple.finder"))
        precondition(!WindowFilterRules.shouldIgnoreApplication(bundleIdentifier: nil))
        precondition(WindowFilterRules.shouldIgnoreWindow(subrole: "Quick Look"))
        precondition(WindowFilterRules.shouldIgnoreWindow(subrole: "AXQuickLook"))
        precondition(!WindowFilterRules.shouldIgnoreWindow(subrole: "AXStandardWindow"))
        precondition(!WindowFilterRules.shouldIgnoreWindow(subrole: nil))
        precondition(WindowFilterRules.shouldIgnoreFinderWindow(
            title: "", subrole: "AXUnknown", isMinimized: false
        ))
        precondition(WindowFilterRules.shouldIgnoreFinderWindow(
            title: "快速查看", subrole: "Quick Look", isMinimized: false
        ))
        precondition(!WindowFilterRules.shouldIgnoreFinderWindow(
            title: "下载", subrole: "AXStandardWindow", isMinimized: false
        ))
        precondition(!WindowFilterRules.shouldIgnoreFinderWindow(
            title: "下载", subrole: "AXDialog", isMinimized: true
        ))

        var liveChecks: [String] = []
        for app in NSWorkspace.shared.runningApplications {
            if let bundleIdentifier = app.bundleIdentifier,
               bundleIdentifier.lowercased().contains("inputmethod") ||
                bundleIdentifier.lowercased().contains("textinput") {
                precondition(WindowFilterRules.shouldIgnoreApplication(
                    bundleIdentifier: bundleIdentifier
                ))
                liveChecks.append("input-method")
            }

            guard app.bundleIdentifier == "com.apple.finder" else { continue }
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
                liveChecks.append("quick-look")
            }
        }
        let liveSummary = Array(Set(liveChecks)).sorted().joined(separator: ",")
        print(liveSummary.isEmpty ? "WINDOW_FILTER_OK static" : "WINDOW_FILTER_OK live-\(liveSummary)")
    }
}
