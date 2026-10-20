@main struct MinimizedWindowEvidenceSelfTest {
    static func main() {
        var known = MinimizedWindowEvidence(knownDocument: true)
        known.observeMiniaturized()
        precondition(known.resolve(liveValue: nil, isLiveWindow: true))
        precondition(!known.resolve(liveValue: nil, isLiveWindow: false))
        precondition(!known.resolve(liveValue: false, isLiveWindow: true))
        precondition(!known.resolve(liveValue: nil, isLiveWindow: true))
        known.observeMiniaturized()
        known.observeRestored()
        precondition(!known.resolve(liveValue: nil, isLiveWindow: true))
        known.observeMiniaturized()
        known.observeDestroyed()
        precondition(!known.resolve(liveValue: true, isLiveWindow: true))
        var unknown = MinimizedWindowEvidence()
        unknown.observeMiniaturized()
        precondition(!unknown.resolve(liveValue: nil, isLiveWindow: true))
        precondition(unknown.resolve(liveValue: true, isLiveWindow: true))
        print("MINIMIZED_EVIDENCE_OK notification-fallback live-false-wins destroyed-wins no-unknown-fallback")
    }
}
