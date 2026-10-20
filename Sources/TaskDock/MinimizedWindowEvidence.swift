/// Keep only affirmative minimization evidence for an existing document window.
/// A destroyed reference must never revive from a cached AXMinimized value.
struct MinimizedWindowEvidence {
    var knownDocument = false
    var minimized = false
    var destroyed = false

    mutating func observeMiniaturized() { minimized = true }
    mutating func observeRestored() { minimized = false }
    mutating func observeDestroyed() { destroyed = true; minimized = false }

    mutating func resolve(liveValue: Bool?, isLiveWindow: Bool) -> Bool {
        guard !destroyed, isLiveWindow else { return false }
        if let liveValue {
            minimized = liveValue
            return liveValue
        }
        return knownDocument && minimized
    }
}
