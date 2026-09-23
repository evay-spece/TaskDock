import Foundation

enum DockCompanionSizing {
    static let baselineDockHeight: CGFloat = 41

    static func scale(for dockHeight: CGFloat) -> CGFloat {
        min(max(dockHeight / baselineDockHeight, 0.82), 1.85)
    }

    static func contentScale(for dockHeight: CGFloat) -> CGFloat {
        let panelScale = scale(for: dockHeight)
        return min(max(1 + (panelScale - 1) * 0.58, 0.9), 1.5)
    }

    static func panelHeight(for dockHeight: CGFloat) -> CGFloat {
        dockHeight + 20 * contentScale(for: dockHeight)
    }

    static func itemHeight(for dockHeight: CGFloat) -> CGFloat {
        min(max(31 * scale(for: dockHeight), 25), max(25, dockHeight - 6))
    }

    static func preferredItemWidth(for dockHeight: CGFloat) -> CGFloat {
        174 * scale(for: dockHeight)
    }

    static func maximumItemWidth(for dockHeight: CGFloat) -> CGFloat {
        216 * scale(for: dockHeight)
    }

    static func minimumItemWidth(for dockHeight: CGFloat) -> CGFloat {
        27 * scale(for: dockHeight)
    }

    static func itemSpacing(for dockHeight: CGFloat) -> CGFloat {
        4 * min(scale(for: dockHeight), 1.5)
    }

    static func isTemporarilyMagnified(
        configuredTileSize: CGFloat,
        observedItemWidths: [CGFloat]
    ) -> Bool {
        guard configuredTileSize > 0, let largestWidth = observedItemWidths.max() else {
            return false
        }
        let threshold = max(configuredTileSize + 6, configuredTileSize * 1.18)
        return largestWidth > threshold
    }
}
