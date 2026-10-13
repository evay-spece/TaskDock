import CoreGraphics

enum WindowSpaceReservationGeometry {
    static let edgeTolerance: CGFloat = 28
    static let minimumWindowHeight: CGFloat = 180
    static let panelBottomTolerance: CGFloat = 32
    static let panelClearance: CGFloat = 2

    // 「轻抬」只改变窗口底边，顶部和左右边保持不动。
    static func liftFrame(from start: CGRect, to end: CGRect, progress: CGFloat) -> CGRect {
        let clamped = min(max(progress, 0), 1)
        let eased = 1 - pow(1 - clamped, 3)
        return CGRect(x: start.minX, y: start.minY,
                      width: start.width + (end.width - start.width) * eased,
                      height: start.height + (end.height - start.height) * eased)
    }

    static func adjustedFrame(
        for windowFrame: CGRect,
        screenFrame: CGRect,
        visibleFrame: CGRect,
        panelFrame: CGRect,
        clearance: CGFloat = panelClearance
    ) -> CGRect? {
        guard panelFrame.minY <= visibleFrame.minY + panelBottomTolerance else { return nil }
        guard windowFrame.width >= visibleFrame.width * 0.35 else { return nil }

        let horizontalOverlap = min(windowFrame.maxX, panelFrame.maxX) - max(windowFrame.minX, panelFrame.minX)
        guard horizontalOverlap > 1 else { return nil }

        let visibleTopAX = screenFrame.maxY - visibleFrame.maxY
        let visibleBottomAX = screenFrame.maxY - visibleFrame.minY
        let topAligned = abs(windowFrame.minY - visibleTopAX) <= edgeTolerance
        let bottomAligned = abs(windowFrame.maxY - visibleBottomAX) <= edgeTolerance
        let occupiesMostVisibleHeight = windowFrame.height >= visibleFrame.height * 0.8
        guard topAligned, bottomAligned || occupiesMostVisibleHeight else { return nil }

        let leftAligned = abs(windowFrame.minX - visibleFrame.minX) <= edgeTolerance
        let rightAligned = abs(windowFrame.maxX - visibleFrame.maxX) <= edgeTolerance
        guard leftAligned || rightAligned else { return nil }

        let reservedTopCocoa = panelFrame.maxY + clearance
        let adjustedBottomAX = screenFrame.maxY - reservedTopCocoa
        let adjustedHeight = adjustedBottomAX - windowFrame.minY
        guard adjustedHeight >= minimumWindowHeight,
              abs(adjustedHeight - windowFrame.height) > 1 else { return nil }

        return CGRect(
            x: windowFrame.minX,
            y: windowFrame.minY,
            width: windowFrame.width,
            height: adjustedHeight
        )
    }

    static func approximatelyEqual(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 3) -> Bool {
        abs(lhs.minX - rhs.minX) <= tolerance &&
        abs(lhs.minY - rhs.minY) <= tolerance &&
        abs(lhs.width - rhs.width) <= tolerance &&
        abs(lhs.height - rhs.height) <= tolerance
    }
}
