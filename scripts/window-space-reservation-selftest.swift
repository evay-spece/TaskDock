import CoreGraphics
import Foundation

@main
struct WindowSpaceReservationSelfTest {
    static func main() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let centeredPanel = CGRect(x: 320, y: 4, width: 800, height: 38)

        let maximized = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let adjusted = WindowSpaceReservationGeometry.adjustedFrame(
            for: maximized, screenFrame: screen, visibleFrame: visible, panelFrame: centeredPanel
        )
        precondition(abs((adjusted?.maxY ?? 0) - 856) < 0.001)
        precondition(abs((adjusted?.minY ?? 0) - maximized.minY) < 0.001)
        let liftedPanel = CGRect(x: 320, y: 4, width: 800, height: 42)
        let lifted = WindowSpaceReservationGeometry.adjustedFrame(
            for: maximized, screenFrame: screen, visibleFrame: visible,
            panelFrame: liftedPanel, clearance: 6
        )
        precondition(abs((lifted?.maxY ?? 0) - 848) < 0.001)
        var lastHeight = maximized.height
        for step in 1...6 {
            let frame = WindowSpaceReservationGeometry.liftFrame(
                from: maximized, to: lifted!, progress: CGFloat(step) / 6
            )
            precondition(frame.minY == maximized.minY && frame.width == maximized.width)
            precondition(frame.height <= lastHeight)
            lastHeight = frame.height
        }
        precondition(abs(lastHeight - lifted!.height) < 0.001)

        let left = CGRect(x: 0, y: 25, width: 720, height: 875)
        let right = CGRect(x: 720, y: 25, width: 720, height: 875)
        let rightPanel = CGRect(x: 1000, y: 4, width: 420, height: 38)
        precondition(WindowSpaceReservationGeometry.adjustedFrame(
            for: left, screenFrame: screen, visibleFrame: visible, panelFrame: rightPanel
        ) == nil)
        precondition(WindowSpaceReservationGeometry.adjustedFrame(
            for: right, screenFrame: screen, visibleFrame: visible, panelFrame: rightPanel
        ) != nil)

        let ordinary = CGRect(x: 100, y: 150, width: 900, height: 600)
        precondition(WindowSpaceReservationGeometry.adjustedFrame(
            for: ordinary, screenFrame: screen, visibleFrame: visible, panelFrame: centeredPanel
        ) == nil)

        // A window shortened by an earlier TaskDock session should still follow the
        // panel after an app restart or a small panel-position change.
        let previouslyReserved = CGRect(x: 0, y: 25, width: 1440, height: 825)
        let movedPanel = CGRect(x: 320, y: 8, width: 800, height: 38)
        let readjusted = WindowSpaceReservationGeometry.adjustedFrame(
            for: previouslyReserved, screenFrame: screen, visibleFrame: visible, panelFrame: movedPanel
        )
        precondition(abs((readjusted?.maxY ?? 0) - 852) < 0.001)

        let raisedPanel = CGRect(x: 320, y: 180, width: 800, height: 38)
        precondition(WindowSpaceReservationGeometry.adjustedFrame(
            for: maximized, screenFrame: screen, visibleFrame: visible, panelFrame: raisedPanel
        ) == nil)

        print("WINDOW_SPACE_RESERVATION_OK")
    }
}
