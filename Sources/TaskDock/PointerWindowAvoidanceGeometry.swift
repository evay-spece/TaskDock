import CoreGraphics

enum PointerWindowAvoidanceGeometry {
    static func isInTriggerRegion(pointer: CGPoint, screen: CGRect) -> Bool {
        screen.contains(pointer) && pointer.y <= screen.minY + screen.height / 3
    }

    /// Covers zoomed and left/right half-screen layouts, including system tiling gaps.
    static func isDefaultAvoidanceWindow(_ window: CGRect, screen: CGRect,
                                        visibleScreen: CGRect, desktopTop: CGFloat) -> Bool {
        let tolerance: CGFloat = 28
        let top = desktopTop - visibleScreen.maxY
        let visibleBottom = desktopTop - visibleScreen.minY
        let physicalBottom = desktopTop - screen.minY
        let fullWidth = abs(window.width - visibleScreen.width) <= tolerance
        let halfWidth = abs(window.width - visibleScreen.width / 2) <= tolerance
        let leftAligned = abs(window.minX - visibleScreen.minX) <= tolerance
        let rightAligned = abs(window.maxX - visibleScreen.maxX) <= tolerance
        let bottomAligned = min(abs(window.maxY - visibleBottom), abs(window.maxY - physicalBottom)) <= tolerance
        return abs(window.minY - top) <= tolerance && bottomAligned &&
            ((fullWidth && leftAligned && rightAligned) || (halfWidth && (leftAligned || rightAligned)))
    }

    /// AX coordinates have downward Y. Only retract a small part of the bottom;
    /// never move the title bar or retrieve a window deliberately placed off-screen.
    static func retractedFrame(window: CGRect, screen: CGRect, panel: CGRect,
                               desktopTop: CGFloat, clearance: CGFloat = 6) -> CGRect? {
        guard window.width > 0, window.height > 0, panel.width > 0, panel.height > 0 else { return nil }
        let screenAX = CGRect(x: screen.minX, y: desktopTop - screen.maxY,
                              width: screen.width, height: screen.height)
        let visible = window.intersection(screenAX)
        guard !visible.isNull,
              visible.width * visible.height >= window.width * window.height * 0.9,
              window.maxY - screenAX.maxY <= 16 else { return nil }
        let panelAX = CGRect(x: panel.minX, y: desktopTop - panel.maxY,
                             width: panel.width, height: panel.height)
        let overlap = window.intersection(panelAX)
        guard !overlap.isNull, overlap.width > 1, overlap.height > 1 else { return nil }
        let delta = window.maxY - (panelAX.minY - clearance)
        let limit = min(panel.height + clearance + 16, window.height * 0.2)
        let height = window.height - delta
        guard delta > 0, delta <= limit, height >= 180 else { return nil }
        return CGRect(x: window.minX, y: window.minY, width: window.width, height: height)
    }

    static func animationFrame(from start: CGRect, to target: CGRect, progress: CGFloat) -> CGRect {
        let progress = min(1, max(0, progress))
        let eased = 1 - pow(1 - progress, 3)
        return CGRect(x: start.minX, y: start.minY, width: start.width,
                      height: start.height + (target.height - start.height) * eased)
    }
}
