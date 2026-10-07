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
        for title in ["", "  ", "\n"] {
            for subrole in ["AXUnknown", "AXStandardWindow", "AXDialog"] {
                precondition(WindowFilterRules.shouldIgnoreFinderWindow(
                    title: title, subrole: subrole, isMinimized: true
                ))
            }
        }
        for subrole in ["AXUnknown", "AXSystemDialog", "AXFloatingWindow", "Quick Look"] {
            precondition(WindowFilterRules.shouldIgnoreFinderWindow(
                title: "Finder", subrole: subrole, isMinimized: true
            ))
        }
        precondition(WindowFilterRules.shouldIgnoreFinderWindow(
            title: "Finder", subrole: nil, isMinimized: true
        ))
        precondition(!WindowFilterRules.shouldIgnoreFinderWindow(
            title: "下载", subrole: "AXStandardWindow", isMinimized: true
        ))
        precondition(WindowFilterRules.shouldKeepMinimizedDocumentWindow(
            bundleIdentifier: "com.microsoft.Excel", title: "工作簿1", subrole: "AXDialog",
            isMinimized: true, isModal: false
        ))
        for identifier in ["com.tencent.xinWeChat", "com.apple.iCal", "com.apple.Notes"] {
            precondition(WindowFilterRules.shouldKeepMinimizedDocumentWindow(
                bundleIdentifier: identifier, title: "文档", subrole: "AXDialog",
                isMinimized: true, isModal: false
            ))
            precondition(!WindowFilterRules.shouldKeepMinimizedDocumentWindow(
                bundleIdentifier: identifier, title: "保存", subrole: "AXDialog",
                isMinimized: false, isModal: false
            ))
            precondition(!WindowFilterRules.shouldKeepMinimizedDocumentWindow(
                bundleIdentifier: identifier, title: "文档", subrole: "AXDialog",
                isMinimized: true, isModal: true
            ))
        }
        precondition(!WindowFilterRules.shouldKeepMinimizedDocumentWindow(
            bundleIdentifier: "com.microsoft.Excel", title: "保存", subrole: "AXDialog",
            isMinimized: false, isModal: true
        ))
        precondition(!WindowFilterRules.shouldKeepMinimizedDocumentWindow(
            bundleIdentifier: "com.microsoft.Excel", title: "", subrole: "AXDialog",
            isMinimized: true, isModal: false
        ))
        precondition(!WindowFilterRules.shouldKeepMinimizedDocumentWindow(
            bundleIdentifier: "com.apple.Preview", title: "图片", subrole: "AXDialog",
            isMinimized: true, isModal: false
        ))

        guard CommandLine.arguments.contains("--live") else {
            print("WINDOW_FILTER_OK static")
            return
        }

        var liveChecks: [String] = []
        for app in NSWorkspace.shared.runningApplications {
            if let identifier = app.bundleIdentifier,
               ["com.tencent.xinWeChat", "com.apple.iCal", "com.apple.Notes"].contains(identifier) {
                let application = AXUIElementCreateApplication(app.processIdentifier)
                var windowValue: CFTypeRef?
                if AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &windowValue) == .success,
                   let windows = windowValue as? [AXUIElement] {
                    for window in windows {
                        var roleValue: CFTypeRef?
                        var subroleValue: CFTypeRef?
                        var minimizedValue: CFTypeRef?
                        var modalValue: CFTypeRef?
                        var titleValue: CFTypeRef?
                        guard AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &roleValue) == .success,
                              (roleValue as? String) == kAXWindowRole,
                              AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleValue) == .success,
                              (subroleValue as? String) == "AXDialog",
                              AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedValue) == .success,
                              (minimizedValue as? Bool) == true,
                              AXUIElementCopyAttributeValue(window, kAXModalAttribute as CFString, &modalValue) == .success,
                              (modalValue as? Bool) == false,
                              AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue) == .success,
                              let title = titleValue as? String else { continue }
                        precondition(WindowFilterRules.shouldKeepMinimizedDocumentWindow(
                            bundleIdentifier: identifier, title: title, subrole: "AXDialog",
                            isMinimized: true, isModal: false
                        ))
                        liveChecks.append("minimized-dialog")
                    }
                }
            }
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
