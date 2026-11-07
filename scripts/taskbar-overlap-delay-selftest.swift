import Foundation

@main
struct TaskbarOverlapDelaySelfTest {
    static func main() {
        var gate = TaskbarOverlapDelayGate()
        precondition(!gate.shouldDarken(overlaps: true, delay: 0.5, now: 10))
        precondition(!gate.shouldDarken(overlaps: true, delay: 0.5, now: 10.4))
        precondition(gate.shouldDarken(overlaps: true, delay: 0.5, now: 10.5))
        precondition(!gate.shouldDarken(overlaps: false, delay: 0.5, now: 10.6))
        precondition(!gate.shouldDarken(overlaps: true, delay: 0.5, now: 10.7))
        precondition(gate.shouldDarken(overlaps: true, delay: 0, now: 10.8))
        print("TASKBAR_OVERLAP_DELAY_OK")
    }
}
