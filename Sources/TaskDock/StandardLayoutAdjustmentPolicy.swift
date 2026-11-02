import Foundation
import CoreGraphics

/// Tracks layout episodes, independently of pointer proximity or our old lift animation.
struct StandardLayoutAdjustmentPolicy {
    private struct Attempt {
        let original: CGRect
        let target: CGRect
        let at: TimeInterval
        var observedTargetAt: TimeInterval?
        var rejected = false
    }
    private var attempts: [String: Attempt] = [:]
    private var candidates: [String: (frame: CGRect, since: TimeInterval)] = [:]

    mutating func retain(_ ids: Set<String>) {
        attempts = attempts.filter { ids.contains($0.key) }
        candidates = candidates.filter { ids.contains($0.key) }
    }

    mutating func adjustment(id: String, frame: CGRect, proposed: CGRect?,
                             dragging: Bool, now: TimeInterval, settleDelay: TimeInterval) -> CGRect? {
        if dragging { candidates.removeValue(forKey: id); return nil }
        if var attempt = attempts[id] {
            if Self.same(frame, attempt.target) {
                if attempt.observedTargetAt == nil { attempt.observedTargetAt = now }
                attempt.rejected = false
                attempts[id] = attempt
                candidates.removeValue(forKey: id)
                return nil
            }
            if Self.same(frame, attempt.original) {
                // A later maximize may recreate identical geometry. An immediate
                // rebound, or a request that never reached its target, gets no retry.
                guard !attempt.rejected, let acceptedAt = attempt.observedTargetAt,
                      now - attempt.at >= 1.5, now - acceptedAt >= 1 else {
                    attempt.rejected = true
                    attempts[id] = attempt
                    return nil
                }
                attempts.removeValue(forKey: id)
            } else if now - attempt.at < 1.5 {
                candidates.removeValue(forKey: id)
                return nil
            } else {
                attempts.removeValue(forKey: id)
            }
        }
        guard let proposed else { candidates.removeValue(forKey: id); return nil }
        if let candidate = candidates[id], Self.same(frame, candidate.frame) {
            guard now - candidate.since >= settleDelay else { return nil }
        } else {
            candidates[id] = (frame, now)
            return nil
        }
        // Mark attempted before calling AX, including a refused write.
        attempts[id] = Attempt(original: frame, target: proposed, at: now)
        candidates.removeValue(forKey: id)
        return proposed
    }

    static func same(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX-b.minX) <= 2 && abs(a.minY-b.minY) <= 2
            && abs(a.width-b.width) <= 2 && abs(a.height-b.height) <= 2
    }

    static func exceedsBottomThreshold(window: CGRect, screen: CGRect, panel: CGRect,
                                       desktopTop: CGFloat, limit: CGFloat) -> Bool {
        let panelAX = CGRect(x: panel.minX, y: desktopTop - panel.maxY,
                             width: panel.width, height: panel.height)
        let overlap = window.intersection(panelAX)
        return !overlap.isNull && overlap.width > 1 && overlap.height > 1
            && window.maxY - (desktopTop - screen.minY) > max(0, limit)
    }

    static func overlappingTarget(window: CGRect, screen: CGRect, visible: CGRect,
                                  panel: CGRect, desktopTop: CGFloat, bottomOverflowLimit: CGFloat = 48) -> CGRect? {
        guard window.width > 0, window.height > 0 else { return nil }
        let screenAX = CGRect(x: screen.minX, y: desktopTop - screen.maxY,
                              width: screen.width, height: screen.height)
        let panelAX = CGRect(x: panel.minX, y: desktopTop - panel.maxY,
                             width: panel.width, height: panel.height)
        let intersection = window.intersection(screenAX)
        let overlap = window.intersection(panelAX)
        guard !intersection.isNull,
              window.maxY - screenAX.maxY <= max(0, bottomOverflowLimit),
              !overlap.isNull, overlap.width > 1, overlap.height > 1 else { return nil }
        let bottom = panelAX.minY - 2
        let moved = window.offsetBy(dx: 0, dy: bottom - window.maxY)
        if window.height < visible.height * 0.75,
           moved.minY >= desktopTop - visible.maxY { return moved }
        let height = bottom - window.minY
        guard height >= 140, height < window.height - 1 else { return nil }
        return CGRect(x: window.minX, y: window.minY, width: window.width, height: height)
    }

    static func target(window: CGRect, screen: CGRect, visible: CGRect,
                       panel: CGRect, desktopTop: CGFloat) -> CGRect? {
        let visibleTop = desktopTop - visible.maxY
        let visibleBottom = desktopTop - visible.minY
        let physicalBottom = desktopTop - screen.minY
        let left = abs(window.minX-visible.minX) <= 12
        let right = abs(window.maxX-visible.maxX) <= 12
        let full = left && right && abs(window.width-visible.width) <= 24
        let half = (left || right) && abs(window.width-visible.width/2) <= 24
        guard full || half, abs(window.minY-visibleTop) <= 12,
              min(abs(window.maxY-visibleBottom), abs(window.maxY-physicalBottom)) <= 12,
              window.minX >= visible.minX-2, window.maxX <= visible.maxX+2,
              window.minY >= visibleTop-2, window.maxY <= physicalBottom+2,
              min(window.maxX, panel.maxX) > max(window.minX, panel.minX) else { return nil }
        let bottom = desktopTop - panel.maxY - 2
        let height = bottom - window.minY
        guard height >= 180, height < window.height-2 else { return nil }
        return CGRect(x: window.minX, y: window.minY, width: window.width, height: height)
    }
}
