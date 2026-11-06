import CoreGraphics

@main
struct FullscreenPresentationSelfTest {
    static func main() {
        let primary = CGRect(x: 0, y: 0, width: 2048, height: 1152)
        let secondary = CGRect(x: 2048, y: 0, width: 1920, height: 1080)

        precondition(FullscreenPresentationDetector.coversDisplay(primary, primary))
        precondition(FullscreenPresentationDetector.coversDisplay(
            CGRect(x: 1, y: 1, width: 2046, height: 1150), primary
        ))
        precondition(!FullscreenPresentationDetector.coversDisplay(
            CGRect(x: 0, y: 24, width: 2048, height: 1128), primary
        )) // Zoomed window still leaves the menu bar visible.
        precondition(!FullscreenPresentationDetector.coversDisplay(
            CGRect(x: 0, y: 0, width: 1024, height: 1152), primary
        )) // Half-screen tiling does not hide TaskDock.
        precondition(!FullscreenPresentationDetector.coversDisplay(secondary, primary))
        precondition(FullscreenPresentationDetector.coversDisplay(secondary, secondary))
        print("FULLSCREEN_PRESENTATION_OK")
    }
}
