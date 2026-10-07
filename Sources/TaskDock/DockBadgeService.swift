import AppKit
import ApplicationServices

/// Reads the labels that the system Dock already exposes for application tiles.
/// A missing or nonnumeric label is not treated as a notification count.
enum DockBadgeService {
    static func badges(for favorites: [FavoriteApp], dockPID: pid_t) -> [String: String] {
        guard !favorites.isEmpty else { return [:] }
        let application = AXUIElementCreateApplication(dockPID)
        AXUIElementSetMessagingTimeout(application, 0.2)
        guard let dockList = findDockList(in: application, depth: 6),
              let items = attribute(dockList, kAXChildrenAttribute) as? [AXUIElement] else {
            return [:]
        }

        var badges: [String: String] = [:]
        for item in items {
            guard let status = attribute(item, "AXStatusLabel") as? String,
                  let badge = normalizedBadge(status),
                  let url = attribute(item, kAXURLAttribute) as? URL else { continue }
            let bundleIdentifier = Bundle(url: url)?.bundleIdentifier
            let title = attribute(item, kAXTitleAttribute) as? String
            for favorite in favorites where matches(
                favorite, tileURL: url, tileBundleIdentifier: bundleIdentifier, tileTitle: title
            ) {
                badges[favorite.id] = badge
            }
        }
        return badges
    }

    static func normalizedBadge(_ rawValue: String) -> String? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasPlus = value.hasSuffix("+")
        let digits = hasPlus ? String(value.dropLast()) : value
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }),
              let count = Int(digits), count > 0 else { return nil }
        if count > 99 { return "99+" }
        return hasPlus ? "\(count)+" : String(count)
    }

    static func matches(
        _ favorite: FavoriteApp,
        tileURL: URL,
        tileBundleIdentifier: String?,
        tileTitle: String?
    ) -> Bool {
        if let favoritePath = favorite.bundlePath,
           normalizedPath(URL(fileURLWithPath: favoritePath)) == normalizedPath(tileURL) {
            return true
        }
        if let bundleIdentifier = favorite.bundleIdentifier,
           bundleIdentifier == tileBundleIdentifier {
            return true
        }
        return favorite.id.hasPrefix("name:")
            && favorite.applicationName.localizedCaseInsensitiveCompare(tileTitle ?? "") == .orderedSame
    }

    private static func normalizedPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path.lowercased()
    }

    private static func findDockList(in element: AXUIElement, depth: Int) -> AXUIElement? {
        if attribute(element, kAXRoleAttribute) as? String == kAXListRole { return element }
        guard depth > 0,
              let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else {
            return nil
        }
        for child in children {
            if let list = findDockList(in: child, depth: depth - 1) { return list }
        }
        return nil
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value as AnyObject?
    }
}

@MainActor
final class FavoriteBadgeStore: ObservableObject {
    @Published private(set) var badges: [String: String] = [:]

    func update(_ newBadges: [String: String]) {
        if badges != newBadges { badges = newBadges }
    }
}
