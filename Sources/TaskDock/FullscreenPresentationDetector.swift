import AppKit
import CoreGraphics

/// Full-screen video can use a borderless window instead of AXFullScreen.
/// Window-server bounds cover both cases without treating an ordinary zoomed
/// window (which stops at the menu bar) as full screen.
enum FullscreenPresentationDetector {
    static func isCoveringTaskbarScreen(excludingPID: pid_t, screen: NSScreen?) -> Bool {
        guard let screen,
              let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              frontmostPID != excludingPID,
              let displayNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return false
        }
        let displayFrame = CGDisplayBounds(CGDirectDisplayID(displayNumber.uint32Value))
        guard displayFrame.width > 0, displayFrame.height > 0,
              let entries = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
              ) as? [[String: Any]] else { return false }

        return entries.contains { entry in
            guard (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == frontmostPID,
                  (entry[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  (entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0.5,
                  let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
                  let windowFrame = CGRect(dictionaryRepresentation: bounds) else { return false }
            return coversDisplay(windowFrame, displayFrame)
        }
    }

    static func coversDisplay(_ window: CGRect, _ display: CGRect) -> Bool {
        let tolerance: CGFloat = 4
        return abs(window.minX - display.minX) <= tolerance
            && abs(window.minY - display.minY) <= tolerance
            && abs(window.maxX - display.maxX) <= tolerance
            && abs(window.maxY - display.maxY) <= tolerance
    }
}
