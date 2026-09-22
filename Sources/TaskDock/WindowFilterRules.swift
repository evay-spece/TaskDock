import Foundation

enum WindowFilterRules {
    private static let transientApplicationBundleIdentifiers: Set<String> = [
        "com.apple.quicklook.QuickLookUIService"
    ]
    private static let transientWindowSubroles: Set<String> = [
        "Quick Look",
        "AXQuickLook"
    ]

    static func shouldIgnoreApplication(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return transientApplicationBundleIdentifiers.contains(bundleIdentifier)
    }

    static func shouldIgnoreWindow(subrole: String?) -> Bool {
        guard let subrole else { return false }
        return transientWindowSubroles.contains(subrole)
    }
}
