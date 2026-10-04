import AppKit
import ApplicationServices

@MainActor
final class TrashStatusService: ObservableObject {
    @Published private(set) var isFull = false
    private var lastRefresh = Date.distantPast

    init() {
        refresh(force: true)
    }

    func refresh(force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastRefresh) >= 1 else { return }
        lastRefresh = now
        // macOS may deny direct access to ~/.Trash without Full Disk Access.
        // Finder's enabled Empty Trash menu item reports the combined system state
        // using the Accessibility permission TaskDock already requires.
        let full = Self.finderTrashIsFull() ?? Self.fileSystemTrashIsFull()
        if isFull != full { isFull = full }
    }

    private static func fileSystemTrashIsFull() -> Bool {
        let homeTrash = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".Trash", isDirectory: true)
        if hasItems(in: homeTrash) { return true }
        let localVolumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeIsLocalKey],
            options: [.skipHiddenVolumes]
        ) ?? []
        return localVolumes.contains { volume in
            guard (try? volume.resourceValues(forKeys: [.volumeIsLocalKey]).volumeIsLocal) == true
            else { return false }
            let volumeTrash = volume
                .appendingPathComponent(".Trashes", isDirectory: true)
                .appendingPathComponent(String(getuid()), isDirectory: true)
            return hasItems(in: volumeTrash)
        }
    }

    static func hasItems(in trash: URL) -> Bool {
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: trash.path) else {
            return false
        }
        return items.contains { $0 != ".DS_Store" }
    }

    static func finderTrashIsFull() -> Bool? {
        guard AXIsProcessTrusted(),
              let finder = NSWorkspace.shared.runningApplications.first(where: {
                  $0.bundleIdentifier == "com.apple.finder"
              }) else { return nil }

        let application = AXUIElementCreateApplication(finder.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.2)
        var menuBarValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application, kAXMenuBarAttribute as CFString, &menuBarValue
        ) == .success, let menuBarValue,
              CFGetTypeID(menuBarValue) == AXUIElementGetTypeID() else { return nil }
        let menuBar = menuBarValue as! AXUIElement
        // Apple menu is first; Finder's application menu is second.
        let menuBarItems = children(of: menuBar)
        guard menuBarItems.count > 1,
              let menu = children(of: menuBarItems[1]).first else { return nil }
        for item in children(of: menu) {
            var keyValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                item, "AXMenuItemCmdVirtualKey" as CFString, &keyValue
            ) == .success, (keyValue as? Int) == 51 else { continue }
            var enabledValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                item, kAXEnabledAttribute as CFString, &enabledValue
            ) == .success else { continue }
            return enabledValue as? Bool
        }
        return nil
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXChildrenAttribute as CFString, &value
        ) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }
}
