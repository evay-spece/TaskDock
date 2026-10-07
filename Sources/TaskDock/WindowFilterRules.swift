import Foundation

enum WindowFilterRules {
    private static let appsWithMinimizedDialogWindows: Set<String> = [
        "com.apple.Terminal",
        "com.apple.Safari",
        "com.apple.systempreferences",
        "com.microsoft.Excel",
        "com.tencent.xinWeChat",
        "com.apple.iCal",
        "com.apple.Notes"
    ]
    private static let transientApplicationBundleIdentifiers: Set<String> = [
        "com.apple.quicklook.QuickLookUIService"
    ]
    private static let inputMethodBundleIdentifierFragments = [
        ".inputmethod.",
        ".textinput"
    ]
    private static let transientWindowSubroles: Set<String> = [
        "Quick Look",
        "AXQuickLook"
    ]

    static func shouldIgnoreApplication(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        if transientApplicationBundleIdentifiers.contains(bundleIdentifier) { return true }

        let normalizedIdentifier = bundleIdentifier.lowercased()
        return inputMethodBundleIdentifierFragments.contains {
            normalizedIdentifier.contains($0)
        }
    }

    static func shouldIgnoreWindow(subrole: String?) -> Bool {
        guard let subrole else { return false }
        return transientWindowSubroles.contains(subrole)
    }

    static func shouldIncludeNormalWindow(subrole: String?) -> Bool {
        subrole == "AXStandardWindow"
    }

    static func shouldIgnoreFinderWindow(title: String, subrole: String?, isMinimized: Bool) -> Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
        // Only normal folder windows can become AXDialog when minimized.
        // Desktop and transient accessibility windows must stay excluded.
        if isMinimized {
            return subrole != "AXStandardWindow" && subrole != "AXDialog"
        }
        return subrole != "AXStandardWindow"
    }

    static func shouldKeepMinimizedDocumentWindow(
        bundleIdentifier: String?,
        title: String,
        subrole: String?,
        isMinimized: Bool,
        isModal: Bool
    ) -> Bool {
        bundleIdentifier.map { appsWithMinimizedDialogWindows.contains($0) } == true &&
            isMinimized && !isModal &&
            (!title.isEmpty || bundleIdentifier == "com.apple.systempreferences") &&
            subrole == "AXDialog"
    }
}
