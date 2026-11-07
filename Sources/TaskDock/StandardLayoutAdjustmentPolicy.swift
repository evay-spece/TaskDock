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
        var failedAt: TimeInterval?
        var retryCount = 0
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
        var retryCount = 0
        if var attempt = attempts[id] {
            if Self.same(frame, attempt.target) {
                if attempt.observedTargetAt == nil { attempt.observedTargetAt = now }
                attempt.rejected = false
                attempt.failedAt = nil
                attempts[id] = attempt
                candidates.removeValue(forKey: id)
                return nil
            }
            if Self.same(frame, attempt.original) {
                if proposed.map({ !Self.same($0, attempt.target) }) == true {
                    attempts.removeValue(forKey: id)
                    candidates.removeValue(forKey: id)
                } else if attempt.rejected {
                    return nil
                } else if let failedAt = attempt.failedAt {
                    guard attempt.retryCount < 2, now - failedAt >= 1 else { return nil }
                    retryCount = attempt.retryCount + 1
                    attempts.removeValue(forKey: id)
                } else if let acceptedAt = attempt.observedTargetAt {
                    // An immediate app rebound should not cause a visible loop.
                    guard now - attempt.at >= 1.5, now - acceptedAt >= 1 else {
                        attempt.rejected = true
                        attempts[id] = attempt
                        return nil
                    }
                    attempts.removeValue(forKey: id)
                } else if now - attempt.at >= 1.5 {
                    // The first AX write never reached its target. Retry only twice.
                    attempt.failedAt = now
                    attempts[id] = attempt
                    return nil
                } else {
                    return nil
                }
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
        attempts[id] = Attempt(original: frame, target: proposed, at: now,
                               retryCount: retryCount)
        candidates.removeValue(forKey: id)
        return proposed
    }

    mutating func accepted(id: String, now: TimeInterval) {
        guard var attempt = attempts[id] else { return }
        attempt.observedTargetAt = now
        attempt.failedAt = nil
        attempts[id] = attempt
    }

    mutating func failed(id: String, now: TimeInterval) {
        guard var attempt = attempts[id] else { return }
        attempt.failedAt = now
        attempts[id] = attempt
    }

    static func same(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX-b.minX) <= 2 && abs(a.minY-b.minY) <= 2
            && abs(a.width-b.width) <= 2 && abs(a.height-b.height) <= 2
    }

    static func exceedsBottomThreshold(window: CGRect, screen: CGRect, panel: CGRect,
                                       desktopTop: CGFloat, limit: CGFloat) -> Bool {
        guard overlapsPanel(window: window, panel: panel, desktopTop: desktopTop) else { return false }
        return window.maxY - (desktopTop - screen.minY) > max(0, limit)
    }

    static func overlapsPanel(window: CGRect, panel: CGRect, desktopTop: CGFloat) -> Bool {
        let panelAX = CGRect(x: panel.minX, y: desktopTop - panel.maxY,
                             width: panel.width, height: panel.height)
        let overlap = window.intersection(panelAX)
        return !overlap.isNull && overlap.width > 1 && overlap.height > 1
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
