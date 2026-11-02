import Foundation
import CoreGraphics

@main
struct WindowAvoidanceAnimationSelfTest {
    static func main() {
        let start = CGRect(x: 100, y: 300, width: 600, height: 500)
        for target in [start.offsetBy(dx: 0, dy: -60),
                       CGRect(x: 100, y: 300, width: 600, height: 440)] {
            var previous = start
            for frame in 0...120 {
                let progress = WindowAvoidanceAnimationGeometry.animationProgress(
                    elapsed: Double(frame) / 120 * 0.35, duration: 0.35)
                let value = WindowAvoidanceAnimationGeometry.animationFrame(from: start, to: target, progress: progress)
                precondition(value.minX == start.minX && value.width == start.width)
                precondition(value.minY <= previous.minY && value.minY >= target.minY)
                precondition(value.height <= previous.height && value.height >= target.height)
                previous = value
            }
            precondition(previous == target)
        }
        precondition(WindowAvoidanceAnimationGeometry.animationProgress(elapsed: -1) == 0)
        precondition(WindowAvoidanceAnimationGeometry.animationProgress(elapsed: 1) == 1)
        precondition(WindowAvoidanceAnimationGeometry.nextAnimationDelay(elapsed: 0) > 0)
        precondition(WindowAvoidanceAnimationGeometry.nextAnimationDelay(elapsed: 1) == 0)
        let defaults = UserDefaults.standard
        let old = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(old, forName: UserDefaults.argumentDomain) }
        for (value, expected) in [(0.35, 0.35), (-1.0, 0.08), (5.0, 0.6), (Double.nan, 0.24)] {
            var domain = old
            domain["taskdock.pointerAvoidanceAnimationDurationV1"] = value
            defaults.setVolatileDomain(domain, forName: UserDefaults.argumentDomain)
            precondition(WindowAvoidanceAnimationSettings.animationDuration == expected)
        }
        print("WINDOW_AVOIDANCE_ANIMATION_OK move resize monotonic deadlines saved-duration-preserved")
    }
}
