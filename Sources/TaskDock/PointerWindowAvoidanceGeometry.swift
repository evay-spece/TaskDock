import CoreGraphics
import Foundation

enum PointerWindowAvoidanceSettings {
    static let animationDurationKey = "taskdock.pointerAvoidanceAnimationDurationV1"
    static let triggerDelayKey = "taskdock.pointerAvoidanceTriggerDelayV1"
    static let tiledDelayKey = "taskdock.tiledAvoidanceTriggerDelayV1"
    static let defaultAnimationDuration: TimeInterval = 0.24
    static let defaultTriggerDelay: TimeInterval = 0

    static var animationDuration: TimeInterval {
        value(for: animationDurationKey, fallback: defaultAnimationDuration, range: 0.08...0.6)
    }

    static var triggerDelay: TimeInterval {
        value(for: triggerDelayKey, fallback: defaultTriggerDelay, range: 0...1.5)
    }
    static var tiledDelay: TimeInterval {
        value(for: tiledDelayKey, fallback: 0, range: 0...2)
    }

    private static func value(for key: String, fallback: TimeInterval,
                              range: ClosedRange<TimeInterval>) -> TimeInterval {
        let stored = (UserDefaults.standard.object(forKey: key) as? NSNumber)?.doubleValue ?? fallback
        return stored.isFinite ? min(range.upperBound, max(range.lowerBound, stored)) : fallback
    }
}

enum PointerWindowAvoidanceGeometry {
    static func isInTriggerRegion(pointer: CGPoint, screen: CGRect) -> Bool {
        screen.contains(pointer) && pointer.y <= screen.minY + screen.height / 3
    }

    /// Covers zoomed, half/third-screen and near-full-height edge layouts with tiling gaps.
    static func isDefaultAvoidanceWindow(_ window: CGRect, screen: CGRect,
                                        visibleScreen: CGRect, desktopTop: CGFloat) -> Bool {
        let tolerance: CGFloat = 48
        let top = desktopTop - visibleScreen.maxY
        let visibleBottom = desktopTop - visibleScreen.minY
        let physicalBottom = desktopTop - screen.minY
        let fullWidth = abs(window.width - visibleScreen.width) <= tolerance
        let halfWidth = abs(window.width - visibleScreen.width / 2) <= tolerance
        let leftAligned = abs(window.minX - visibleScreen.minX) <= tolerance
        let rightAligned = abs(window.maxX - visibleScreen.maxX) <= tolerance
        let bottomAligned = min(abs(window.maxY - visibleBottom), abs(window.maxY - physicalBottom)) <= tolerance
        let tallEdgeWindow = window.height >= visibleScreen.height * 0.75 &&
            window.width >= visibleScreen.width * 0.30 && (leftAligned || rightAligned)
        return abs(window.minY - top) <= tolerance && bottomAligned &&
            ((fullWidth && leftAligned && rightAligned) || (halfWidth && (leftAligned || rightAligned)) || tallEdgeWindow)
    }

    /// AX coordinates have downward Y. Only retract a small part of the bottom;
    /// never move the title bar or retrieve a window deliberately placed off-screen.
    static func retractedFrame(window: CGRect, screen: CGRect, panel: CGRect,
                               desktopTop: CGFloat, clearance: CGFloat = 2) -> CGRect? {
        guard window.width > 0, window.height > 0, panel.width > 0, panel.height > 0 else { return nil }
        let screenAX = CGRect(x: screen.minX, y: desktopTop - screen.maxY,
                              width: screen.width, height: screen.height)
        let visible = window.intersection(screenAX)
        guard !visible.isNull,
              visible.width * visible.height >= window.width * window.height * 0.8,
              window.maxY - screenAX.maxY <= 48 else { return nil }
        let panelAX = CGRect(x: panel.minX, y: desktopTop - panel.maxY,
                             width: panel.width, height: panel.height)
        let overlap = window.intersection(panelAX)
        guard !overlap.isNull, overlap.width > 1, overlap.height > 1 else { return nil }
        let delta = window.maxY - (panelAX.minY - clearance)
        let limit = min(panel.height + clearance + 48, window.height * 0.3)
        let height = window.height - delta
        guard delta > 0, delta <= limit, height >= 140 else { return nil }
        return CGRect(x: window.minX, y: window.minY, width: window.width, height: height)
    }

    /// Tall windows retain their title-bar position; compact windows retain their size.
    static func adjustedFrame(window: CGRect, screen: CGRect, visibleScreen: CGRect,
                              panel: CGRect, desktopTop: CGFloat, clearance: CGFloat = 2) -> CGRect? {
        if window.height >= visibleScreen.height * 0.75 {
            return retractedFrame(window: window, screen: screen, panel: panel,
                                  desktopTop: desktopTop, clearance: clearance)
        }
        guard window.width > 0, window.height > 0, panel.width > 0, panel.height > 0 else { return nil }
        let screenAX = CGRect(x: screen.minX, y: desktopTop - screen.maxY,
                              width: screen.width, height: screen.height)
        let visible = window.intersection(screenAX)
        let panelAX = CGRect(x: panel.minX, y: desktopTop - panel.maxY,
                             width: panel.width, height: panel.height)
        let overlap = window.intersection(panelAX)
        guard !visible.isNull, visible.width * visible.height >= window.width * window.height * 0.8,
              window.maxY - screenAX.maxY <= 48,
              !overlap.isNull, overlap.width > 1, overlap.height > 1 else { return nil }
        let delta = window.maxY - (panelAX.minY - clearance)
        let target = window.offsetBy(dx: 0, dy: -delta)
        guard delta > 0, delta <= panel.height + clearance + 48,
              target.minY >= desktopTop - visibleScreen.maxY else { return nil }
        return target
    }

    /// AX can report intermediate system-animation frames after accepting a request.
    static func isOnAnimationPath(_ frame: CGRect, from start: CGRect, to target: CGRect,
                                  tolerance: CGFloat = 2) -> Bool {
        func between(_ value: CGFloat, _ a: CGFloat, _ b: CGFloat) -> Bool {
            value >= min(a, b) - tolerance && value <= max(a, b) + tolerance
        }
        return between(frame.minX, start.minX, target.minX) &&
            between(frame.minY, start.minY, target.minY) &&
            between(frame.width, start.width, target.width) &&
            between(frame.height, start.height, target.height)
    }

    static func canRetryDefaultLayout(isDefault: Bool, elapsed: TimeInterval, retries: Int) -> Bool {
        isDefault && elapsed >= 1 && retries < 2
    }

    static func hasReachedTriggerDelay(elapsed: TimeInterval, delay: TimeInterval) -> Bool {
        elapsed >= delay
    }

    static func animationProgress(elapsed: TimeInterval,
                                  duration: TimeInterval = PointerWindowAvoidanceSettings.defaultAnimationDuration) -> CGFloat {
        CGFloat(min(1, max(0, elapsed / duration)))
    }

    static func nextAnimationDelay(elapsed: TimeInterval,
                                   duration: TimeInterval = PointerWindowAvoidanceSettings.defaultAnimationDuration) -> TimeInterval {
        let nextTick = (floor(max(0, elapsed) * 60) + 1) / 60
        return max(0, min(duration, nextTick) - elapsed)
    }

    static func animationFrame(from start: CGRect, to target: CGRect, progress: CGFloat) -> CGRect {
        let progress = min(1, max(0, progress))
        let eased = 1 - pow(1 - progress, 3)
        return CGRect(x: start.minX, y: start.minY + (target.minY - start.minY) * eased, width: start.width,
                      height: start.height + (target.height - start.height) * eased)
    }
}
