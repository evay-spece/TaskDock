import AppKit
import ApplicationServices

struct DockGeometrySnapshot {
    let frame: CGRect
    let layoutSignature: String
    let isMagnified: Bool
}

final class DockGeometryService {
    private var cachedBottomDockGeometry: DockGeometrySnapshot?

    func bottomDockGeometry(on screen: NSScreen, minimizedWindowCount: Int) -> DockGeometrySnapshot? {
        guard dockOrientation == "bottom",
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return cachedBottomDockGeometry ?? estimatedBottomDockGeometry(on: screen, minimizedWindowCount: minimizedWindowCount)
        }

        let application = AXUIElementCreateApplication(dock.processIdentifier)
        guard let dockList = findDockList(in: application, remainingDepth: 6),
              let position = pointAttribute(dockList, kAXPositionAttribute),
              let size = sizeAttribute(dockList, kAXSizeAttribute),
              size.width > 0, size.height > 0 else {
            return estimatedBottomDockGeometry(
                on: screen,
                minimizedWindowCount: minimizedWindowCount
            ) ?? cachedBottomDockGeometry
        }

        let screenFrame = screen.frame
        let width = min(size.width, screenFrame.width)
        let x = min(max(position.x, screenFrame.minX), screenFrame.maxX - width)
        let frame = CGRect(
            x: x,
            y: screenFrame.minY + 4,
            width: width,
            height: size.height
        )
        let dockItems = copyAttribute(dockList, kAXChildrenAttribute) as? [AXUIElement] ?? []
        let itemCount = dockItems.count
        let tileSize = dockTileSize
        let observedItemWidths = dockItems.compactMap {
            sizeAttribute($0, kAXSizeAttribute)?.width
        }.filter { $0 > 1 }
        let snapshot = DockGeometrySnapshot(
            frame: frame,
            layoutSignature: "\(itemCount)|\(minimizedWindowCount)|\(Int(tileSize.rounded()))",
            isMagnified: DockCompanionSizing.isTemporarilyMagnified(
                configuredTileSize: tileSize,
                observedItemWidths: observedItemWidths
            )
        )
        if !snapshot.isMagnified {
            cachedBottomDockGeometry = snapshot
        }
        return snapshot
    }

    private var dockOrientation: String {
        UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation") ?? "bottom"
    }

    private var dockTileSize: CGFloat {
        let defaults = UserDefaults.standard.persistentDomain(forName: "com.apple.dock")
        return CGFloat((defaults?["tilesize"] as? NSNumber)?.doubleValue ?? 48)
    }

    private func estimatedBottomDockGeometry(on screen: NSScreen, minimizedWindowCount: Int) -> DockGeometrySnapshot? {
        guard let defaults = UserDefaults.standard.persistentDomain(forName: "com.apple.dock") else {
            return nil
        }
        let apps = defaults["persistent-apps"] as? [[String: Any]] ?? []
        let others = defaults["persistent-others"] as? [[String: Any]] ?? []
        guard !apps.isEmpty || !others.isEmpty else { return nil }

        let tileSize = (defaults["tilesize"] as? NSNumber)?.doubleValue ?? 48
        let step = CGFloat(tileSize + 2)
        let smallSpacerCount = apps.filter { ($0["tile-type"] as? String) == "small-spacer-tile" }.count
        let regularAppCount = max(0, apps.count - smallSpacerCount)
        let minimizesIntoApp = (defaults["minimize-to-application"] as? NSNumber)?.boolValue ?? false
        let minimizedCount = minimizesIntoApp ? 0 : minimizedWindowCount
        // Finder, Trash and the application/document separator are not stored in
        // persistent-apps/persistent-others but always contribute to Dock width.
        let regularTileCount = regularAppCount + others.count + minimizedCount + 2
        let estimatedWidth = CGFloat(regularTileCount) * step
            + CGFloat(smallSpacerCount) * step * 0.5
            + step * 0.45
            + 18
        let width = min(max(estimatedWidth, 120), screen.frame.width - 8)
        let pinning = defaults["pinning"] as? String ?? "middle"
        let x: CGFloat
        switch pinning {
        case "start": x = screen.frame.minX + 4
        case "end": x = screen.frame.maxX - width - 4
        default: x = screen.frame.midX - width / 2
        }
        return DockGeometrySnapshot(
            frame: CGRect(
                x: x,
                y: screen.frame.minY + 4,
                width: width,
                height: CGFloat(tileSize + 11)
            ),
            layoutSignature: "estimated|\(regularTileCount)|\(minimizedWindowCount)|\(Int(tileSize.rounded()))",
            isMagnified: false
        )
    }

    private func findDockList(in element: AXUIElement, remainingDepth: Int) -> AXUIElement? {
        if copyAttribute(element, kAXRoleAttribute) as? String == kAXListRole {
            return element
        }
        guard remainingDepth > 0,
              let children = copyAttribute(element, kAXChildrenAttribute) as? [AXUIElement] else {
            return nil
        }
        for child in children {
            if let result = findDockList(in: child, remainingDepth: remainingDepth - 1) {
                return result
            }
        }
        return nil
    }

    private func pointAttribute(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let value = copyAttribute(element, attribute),
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    private func sizeAttribute(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let value = copyAttribute(element, attribute),
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
        return size
    }

    private func copyAttribute(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as AnyObject?
    }
}
