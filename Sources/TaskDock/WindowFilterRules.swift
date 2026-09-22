import Foundation

enum WindowFilterRules {
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

    static func shouldIgnoreFinderWindow(title: String, subrole: String?, isMinimized: Bool) -> Bool {
        if isMinimized { return false }
        guard !title.isEmpty else { return true }
        return subrole != "AXStandardWindow"
    }
}
