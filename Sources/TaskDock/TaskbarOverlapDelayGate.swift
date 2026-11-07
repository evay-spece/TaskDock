import Foundation

struct TaskbarOverlapDelayGate {
    private var overlapStartedAt: TimeInterval?

    mutating func shouldDarken(overlaps: Bool, delay: TimeInterval, now: TimeInterval) -> Bool {
        guard overlaps else {
            overlapStartedAt = nil
            return false
        }
        if overlapStartedAt == nil { overlapStartedAt = now }
        return now - (overlapStartedAt ?? now) >= max(0, delay)
    }
}
