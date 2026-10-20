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
        precondition(retracted == CGRect(x: 200, y: 300, width: 600, height: 546))
        precondition(target(retracted) == nil)
        let tall = CGRect(x: 200, y: 25, width: 600, height: 875)
        precondition(target(tall) == CGRect(x: 200, y: 25, width: 600, height: 821))
        precondition(target(CGRect(x: 200, y: 500, width: 600, height: 700)) == nil) // far below screen
        precondition(target(CGRect(x: -300, y: 300, width: 600, height: 580)) == nil) // far beyond side
        precondition(target(CGRect(x: 200, y: 700, width: 600, height: 190)) == nil) // excessive relative change
        precondition(target(CGRect(x: 0, y: 300, width: 100, height: 580)) == nil) // no horizontal overlap
        precondition(target(CGRect(x: 200, y: 200, width: 600, height: 400)) == nil) // no vertical overlap
        precondition(target(CGRect(x: 200, y: 25, width: 600, height: 892)) == nil) // >16pt below screen
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
        func tiled(_ window: CGRect) -> Bool {
            PointerWindowAvoidanceGeometry.isDefaultAvoidanceWindow(window, screen: screen,
                visibleScreen: visible, desktopTop: 900)
        }
        for tiledFrame in [CGRect(x: 0, y: 25, width: 1440, height: 875),
                           CGRect(x: 0, y: 25, width: 720, height: 875),
                           CGRect(x: 720, y: 25, width: 720, height: 875),
                           CGRect(x: 8, y: 33, width: 704, height: 859),
                           CGRect(x: 728, y: 33, width: 704, height: 859)] {
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
        print("POINTER_RETRACTION_OK fixed-origin small-overlap offscreen-skip animation-monotonic idempotent offset-screen default-max-left-right")
    }
}
