import Foundation
import CoreGraphics
@main
struct StandardLayoutAdjustmentSelfTest {
    static func main() {
        let screen = CGRect(x: 0, y: 0, width: 2048, height: 1152)
        let visible = CGRect(x: 0, y: 4, width: 2048, height: 1118)
        let panel = CGRect(x: 86, y: 4, width: 1876, height: 54)
        func overlapping(_ frame: CGRect) -> CGRect? {
            StandardLayoutAdjustmentPolicy.overlappingTarget(window: frame, screen: screen,
                visible: visible, panel: panel, desktopTop: 1152)
        }
        let ordinary = CGRect(x: 300, y: 850, width: 500, height: 280)
        precondition(overlapping(ordinary)?.height == ordinary.height)
        precondition(overlapping(ordinary)!.maxY == 1092)
        precondition(overlapping(CGRect(x: 300, y: 30, width: 800, height: 1100))?.height == 1062)
        precondition(overlapping(CGRect(x: -400, y: 850, width: 500, height: 280)) != nil)
        let overflowing = CGRect(x: 300, y: 850, width: 500, height: 400)
        precondition(overlapping(overflowing) == nil)
        precondition(StandardLayoutAdjustmentPolicy.overlappingTarget(window: overflowing,
            screen: screen, visible: visible, panel: panel, desktopTop: 1152,
            bottomOverflowLimit: 120) != nil)
        precondition(overlapping(CGRect(x: 300, y: 950, width: 500, height: 400)) == nil)
        precondition(overlapping(CGRect(x: 300, y: 100, width: 500, height: 400)) == nil)
        precondition(StandardLayoutAdjustmentPolicy.exceedsBottomThreshold(window: overflowing,
            screen: screen, panel: panel, desktopTop: 1152, limit: 48))
        precondition(!StandardLayoutAdjustmentPolicy.exceedsBottomThreshold(window: overflowing,
            screen: screen, panel: panel, desktopTop: 1152, limit: 120))
        precondition(!StandardLayoutAdjustmentPolicy.exceedsBottomThreshold(
            window: overflowing.offsetBy(dx: 3000, dy: 0), screen: screen, panel: panel,
            desktopTop: 1152, limit: 48))
        let full = CGRect(x: 0, y: 30, width: 2048, height: 1118)
        let half = CGRect(x: 1024, y: 30, width: 1024, height: 1118)
        func target(_ frame: CGRect) -> CGRect? {
            StandardLayoutAdjustmentPolicy.target(window: frame, screen: screen,
                visible: visible, panel: panel, desktopTop: 1152)
        }
        let adjusted = target(full)!
        precondition(adjusted == CGRect(x: 0, y: 30, width: 2048, height: 1062))
        precondition(target(half)?.height == 1062)
        precondition(target(CGRect(x: 100, y: 648, width: 700, height: 500)) == nil)
        precondition(target(CGRect(x: 0, y: 30, width: 700, height: 1118)) == nil)
        precondition(target(full.offsetBy(dx: -10, dy: 0)) == nil)
        precondition(target(full.offsetBy(dx: 0, dy: 80)) == nil)
        var policy = StandardLayoutAdjustmentPolicy()
        func observe(_ f: CGRect, _ t: Double, dragging: Bool = false) -> CGRect? {
            policy.adjustment(id: "window", frame: f, proposed: target(f), dragging: dragging,
                now: t, settleDelay: 0.35)
        }
        precondition(observe(full, 0) == nil)
        precondition(observe(full, 0.2) == nil)
        precondition(observe(full, 0.4) == adjusted)
        precondition(observe(adjusted, 0.6) == nil)
        precondition(observe(full, 0.8) == nil) // App immediately rebounds.
        for t in [1.0, 2.0, 5.0, 10.0] { precondition(observe(full, t) == nil) }
        precondition(observe(half, 12) == nil)
        precondition(observe(half, 12.4) == target(half))
        precondition(observe(target(half)!, 12.6) == nil)
        precondition(observe(half, 15) == nil) // Later explicit tile is a new episode.
        precondition(observe(half, 15.4) == target(half))
        policy = StandardLayoutAdjustmentPolicy()
        precondition(observe(full, 20, dragging: true) == nil)
        precondition(observe(full, 21, dragging: true) == nil)
        precondition(observe(full, 22) == nil)
        precondition(observe(full, 22.4) == adjusted)
        policy.retain([])
        precondition(observe(full, 30) == nil)
        print("STANDARD_LAYOUT_ONCE_OK full half ordinary offscreen settle drag rebound new-layout")
    }
}
