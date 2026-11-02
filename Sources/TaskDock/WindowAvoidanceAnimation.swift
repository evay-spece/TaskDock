import CoreGraphics
import Foundation

enum WindowAvoidanceAnimationSettings {
    static let animationDurationKey = "taskdock.pointerAvoidanceAnimationDurationV1"
    static let defaultAnimationDuration: TimeInterval = 0.24
    static var animationDuration: TimeInterval {
        let value = UserDefaults.standard.object(forKey: animationDurationKey) as? Double ?? defaultAnimationDuration
        return value.isFinite ? min(0.6, max(0.08, value)) : defaultAnimationDuration
    }
}

enum WindowAvoidanceAnimationGeometry {
    static func animationProgress(elapsed: TimeInterval,
                                  duration: TimeInterval = WindowAvoidanceAnimationSettings.defaultAnimationDuration) -> CGFloat {
        CGFloat(min(1, max(0, elapsed / duration)))
    }

    static func nextAnimationDelay(elapsed: TimeInterval,
                                   duration: TimeInterval = WindowAvoidanceAnimationSettings.defaultAnimationDuration) -> TimeInterval {
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
