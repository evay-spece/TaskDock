import CoreGraphics

@main struct PointerAvoidanceSelfTest {
    static func main() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let bar = CGRect(x: 147, y: 4, width: 1146, height: 44)
        precondition(PointerWindowAvoidanceGeometry.isInTriggerRegion(pointer: CGPoint(x: 700, y: 299), screen: screen))
        precondition(!PointerWindowAvoidanceGeometry.isInTriggerRegion(pointer: CGPoint(x: 700, y: 301), screen: screen))
        precondition(!PointerWindowAvoidanceGeometry.isInTriggerRegion(pointer: CGPoint(x: 1500, y: 100), screen: screen))
        func target(_ window: CGRect) -> CGRect? {
            PointerWindowAvoidanceGeometry.retractedFrame(window: window, screen: screen, panel: bar, desktopTop: 900)
        }
        let window = CGRect(x: 200, y: 300, width: 600, height: 580)
        let retracted = target(window)!
        precondition(retracted == CGRect(x: 200, y: 300, width: 600, height: 550))
        precondition(target(retracted) == nil)
        let tall = CGRect(x: 200, y: 25, width: 600, height: 875)
        precondition(target(tall) == CGRect(x: 200, y: 25, width: 600, height: 825))
        precondition(target(CGRect(x: 200, y: 500, width: 600, height: 700)) == nil) // far below screen
        precondition(target(CGRect(x: -300, y: 300, width: 600, height: 580)) == nil) // far beyond side
        // Smaller windows and slight overflow now qualify; top and width remain fixed.
        let small = CGRect(x: 200, y: 700, width: 600, height: 190)
        precondition(target(small) == CGRect(x: 200, y: 700, width: 600, height: 150))
        let slightOverflow = CGRect(x: 200, y: 25, width: 600, height: 892)
        precondition(target(slightOverflow) == CGRect(x: 200, y: 25, width: 600, height: 825))
        precondition(target(CGRect(x: 200, y: 730, width: 600, height: 160)) == nil) // would leave <140pt
        precondition(target(CGRect(x: 200, y: 680, width: 600, height: 265)) == nil) // >30% shrink
        precondition(target(CGRect(x: 200, y: 25, width: 600, height: 924)) == nil) // >48pt below screen
        precondition(retracted.maxY == 900 - bar.maxY - 2)
        precondition(target(CGRect(x: 0, y: 300, width: 100, height: 580)) == nil) // no horizontal overlap
        precondition(target(CGRect(x: 200, y: 200, width: 600, height: 400)) == nil) // no vertical overlap
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
        func tiled(_ window: CGRect) -> Bool {
            PointerWindowAvoidanceGeometry.isDefaultAvoidanceWindow(window, screen: screen,
                visibleScreen: visible, desktopTop: 900)
        }
        for tiledFrame in [CGRect(x: 0, y: 25, width: 1440, height: 875),
                           CGRect(x: 0, y: 25, width: 720, height: 875),
                           CGRect(x: 720, y: 25, width: 720, height: 875),
                           CGRect(x: 8, y: 33, width: 704, height: 859),
                           CGRect(x: 728, y: 33, width: 704, height: 859),
                           CGRect(x: 8, y: 25, width: 464, height: 899),
                           CGRect(x: 968, y: 25, width: 464, height: 899)] {
            precondition(tiled(tiledFrame))
            precondition(target(tiledFrame) != nil)
            let offset = tiledFrame.offsetBy(dx: -1440, dy: 900)
            precondition(PointerWindowAvoidanceGeometry.isDefaultAvoidanceWindow(offset,
                screen: screen.offsetBy(dx: -1440, dy: -900),
                visibleScreen: visible.offsetBy(dx: -1440, dy: -900), desktopTop: 900))
        }
        precondition(!tiled(window))
        precondition(!tiled(CGRect(x: 360, y: 25, width: 720, height: 875))) // centered, not half-screen
        precondition(!tiled(CGRect(x: 0, y: 25, width: 720, height: 1100))) // out of screen
        var previous = window.height
        for step in 1...8 {
            let frame = PointerWindowAvoidanceGeometry.animationFrame(from: window, to: retracted, progress: CGFloat(step) / 8)
            precondition(frame.origin == window.origin && frame.width == window.width)
            precondition(frame.height < previous && frame.height >= retracted.height)
            previous = frame.height
        }
        precondition(previous == retracted.height)
        let offsetScreen = screen.offsetBy(dx: -1440, dy: -900)
        precondition(PointerWindowAvoidanceGeometry.isInTriggerRegion(pointer: CGPoint(x: -500, y: -800), screen: offsetScreen))
        let offsetTarget = PointerWindowAvoidanceGeometry.retractedFrame(window: window.offsetBy(dx: -1440, dy: 900),
            screen: offsetScreen, panel: bar.offsetBy(dx: -1440, dy: -900), desktopTop: 900)!
        precondition(offsetTarget == retracted.offsetBy(dx: -1440, dy: 900))
        func adjusted(_ frame: CGRect) -> CGRect? {
            PointerWindowAvoidanceGeometry.adjustedFrame(window: frame, screen: screen,
                visibleScreen: visible, panel: bar, desktopTop: 900)
        }
        precondition(adjusted(tall) == target(tall))
        let moved = adjusted(small)!
        precondition(moved == CGRect(x: 200, y: 660, width: 600, height: 190))
        precondition(adjusted(moved) == nil)
        precondition(adjusted(window) == CGRect(x: 200, y: 270, width: 600, height: 580))
        precondition(adjusted(CGRect(x: 200, y: 730, width: 600, height: 160))?.height == 160)
        precondition(adjusted(CGRect(x: 200, y: 500, width: 600, height: 700)) == nil)
        precondition(adjusted(CGRect(x: -300, y: 700, width: 600, height: 190)) == nil)
        precondition(adjusted(CGRect(x: 200, y: 700, width: 600, height: 249)) == nil)
        precondition(adjusted(CGRect(x: 0, y: 700, width: 100, height: 190)) == nil)
        var previousY = small.minY
        for step in 1...8 {
            let frame = PointerWindowAvoidanceGeometry.animationFrame(from: small, to: moved, progress: CGFloat(step) / 8)
            precondition(frame.size == small.size && frame.minX == small.minX)
            precondition(frame.minY < previousY && frame.minY >= moved.minY)
            previousY = frame.minY
        }
        precondition(previousY == moved.minY)
        precondition(PointerWindowAvoidanceGeometry.adjustedFrame(
            window: small.offsetBy(dx: -1440, dy: 900), screen: offsetScreen,
            visibleScreen: visible.offsetBy(dx: -1440, dy: -900),
            panel: bar.offsetBy(dx: -1440, dy: -900), desktopTop: 900) == moved.offsetBy(dx: -1440, dy: 900))
        precondition(PointerWindowAvoidanceGeometry.animationProgress(elapsed: -0.1) == 0)
        precondition(PointerWindowAvoidanceGeometry.animationProgress(elapsed: 0.12) == 0.5)
        precondition(PointerWindowAvoidanceGeometry.animationProgress(elapsed: 0.30) == 1)
        precondition(PointerWindowAvoidanceGeometry.animationProgress(elapsed: 0.12, duration: 0.48) == 0.25)
        precondition(PointerWindowAvoidanceGeometry.animationProgress(elapsed: 0.12, duration: 0.12) == 1)
        precondition(!PointerWindowAvoidanceGeometry.hasReachedTriggerDelay(elapsed: 0.14, delay: 0.15))
        precondition(PointerWindowAvoidanceGeometry.hasReachedTriggerDelay(elapsed: 0.15, delay: 0.15))
        for elapsed in [0.0, 0.018, 0.053, 0.199, 0.235, 0.26] {
            let delay = PointerWindowAvoidanceGeometry.nextAnimationDelay(elapsed: elapsed)
            precondition(delay >= 0 && delay <= 1.0 / 60.0 + 0.000001)
            if elapsed < 0.24 { precondition(elapsed + delay <= 0.24 + 0.000001) }
        }
        // A delayed callback advances by elapsed time rather than replaying old steps.
        let delayed = PointerWindowAvoidanceGeometry.animationFrame(from: small, to: moved,
            progress: PointerWindowAvoidanceGeometry.animationProgress(elapsed: 0.30))
        precondition(delayed == moved)
        precondition(PointerWindowAvoidanceGeometry.isOnAnimationPath(window, from: window, to: retracted))
        precondition(PointerWindowAvoidanceGeometry.isOnAnimationPath(
            CGRect(x: 200, y: 300, width: 600, height: 565), from: window, to: retracted))
        precondition(!PointerWindowAvoidanceGeometry.isOnAnimationPath(
            window.offsetBy(dx: 10, dy: 0), from: window, to: retracted))
        precondition(!PointerWindowAvoidanceGeometry.isOnAnimationPath(
            CGRect(x: 200, y: 300, width: 600, height: 600), from: window, to: retracted))
        precondition(PointerWindowAvoidanceGeometry.isOnAnimationPath(small, from: small, to: moved))
        precondition(PointerWindowAvoidanceGeometry.canRetryDefaultLayout(isDefault: true, elapsed: 1.1, retries: 0))
        precondition(!PointerWindowAvoidanceGeometry.canRetryDefaultLayout(isDefault: false, elapsed: 5, retries: 0))
        precondition(!PointerWindowAvoidanceGeometry.canRetryDefaultLayout(isDefault: true, elapsed: 0.5, retries: 0))
        precondition(!PointerWindowAvoidanceGeometry.canRetryDefaultLayout(isDefault: true, elapsed: 5, retries: 2))
        let tiledOriginal = CGRect(x: 720, y: 25, width: 720, height: 875)
        let tiledTarget = target(tiledOriginal)!
        let interrupted = CGRect(x: 720, y: 25, width: 720, height: tiledTarget.height + 5)
        precondition(PointerWindowAvoidanceGeometry.isOnAnimationPath(interrupted, from: tiledOriginal, to: tiledTarget))
        precondition(adjusted(interrupted) == tiledTarget)
        precondition(!PointerWindowAvoidanceGeometry.isOnAnimationPath(interrupted.offsetBy(dx: 20, dy: 0), from: tiledOriginal, to: tiledTarget))
        let tallerBar = CGRect(x: 147, y: 4, width: 1146, height: 50)
        let tallerTarget = PointerWindowAvoidanceGeometry.retractedFrame(window: tiledOriginal,
            screen: screen, panel: tallerBar, desktopTop: 900)!
        let partiallyRetracted = CGRect(x: 720, y: 25, width: 720, height: tallerTarget.height + 5)
        precondition(!tiled(partiallyRetracted)) // crossed the 48pt default-layout tolerance
        precondition(PointerWindowAvoidanceGeometry.isOnAnimationPath(partiallyRetracted, from: tiledOriginal, to: tallerTarget))
        precondition(PointerWindowAvoidanceGeometry.adjustedFrame(window: partiallyRetracted,
            screen: screen, visibleScreen: visible, panel: tallerBar, desktopTop: 900) == tallerTarget)
        print("POINTER_RETRACTION_OK interrupted-tiled-recovery async-readback bounded-default-retry clock-based-60hz deadline-catchup large-resize small-move fixed-origin small-overlap offscreen-skip animation-monotonic idempotent offset-screen default-max-left-right thirds slight-overflow smaller-windows gap-2pt")
    }
}
