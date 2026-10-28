import AppKit

@main
struct ApplicationVisibilitySelfTest {
    @MainActor final class App {
        let pid: pid_t
        var hidden = false
        var terminated = false
        var hideCalls = 0
        var unhideCalls = 0
        var hideSucceedsAfter = 1
        var unhideSucceedsAfter = 1
        init(_ pid: pid_t) { self.pid = pid }
        var target: ApplicationVisibilityToggle.Target {
            .init(pid: pid, isHidden: { self.hidden }, isTerminated: { self.terminated }, hide: {
                self.hideCalls += 1
                if self.hideCalls >= self.hideSucceedsAfter { self.hidden = true }
            }, unhide: {
                self.unhideCalls += 1
                if self.unhideCalls >= self.unhideSucceedsAfter { self.hidden = false }
            })
        }
    }
    @MainActor final class Clock {
        var time: TimeInterval = 0
        var jobs: [(TimeInterval, () -> Void)] = []
        func advance(_ until: TimeInterval) {
            while let next = jobs.enumerated().filter({ $0.element.0 <= until })
                .min(by: { $0.element.0 < $1.element.0 }) {
                let job = jobs.remove(at: next.offset)
                time = job.0
                job.1()
            }
            time = until
        }
        func toggle() -> ApplicationVisibilityToggle {
            .init(now: { self.time }, schedule: { self.jobs.append((self.time + $0, $1)) })
        }
    }
    @MainActor static func main() {
        let clock = Clock(), toggle = clock.toggle()
        let slow = App(10), alreadyHidden = App(11), dead = App(12)
        slow.hideSucceedsAfter = 3
        alreadyHidden.hidden = true
        dead.terminated = true
        toggle.hide(targets: [slow.target, alreadyHidden.target, dead.target])
        clock.advance(0.1)
        toggle.synchronize()
        precondition(toggle.canRestore && !slow.hidden)
        clock.advance(1.2)
        precondition(slow.hidden && slow.hideCalls == 3)
        precondition(toggle.hiddenPIDs == [10])
        toggle.restore()
        clock.advance(2)
        precondition(!slow.hidden && alreadyHidden.hidden && dead.hideCalls == 0)

        let c2 = Clock(), t2 = c2.toggle(), immediate = App(20)
        t2.hide(targets: [immediate.target])
        t2.restore()
        c2.advance(2)
        precondition(!immediate.hidden && immediate.hideCalls == 1,
                     "Restore must cancel delayed hide attempts")

        let c3 = Clock(), t3 = c3.toggle(), refusing = App(30)
        refusing.hideSucceedsAfter = 100
        t3.hide(targets: [refusing.target])
        c3.advance(2)
        precondition(refusing.hideCalls == 5 && !t3.canRestore,
                     "Retries are bounded; failed apps must not remain in the restore snapshot")

        let c4 = Clock(), t4 = c4.toggle(), restarting = App(40)
        restarting.unhideSucceedsAfter = 2
        t4.hide(targets: [restarting.target]); t4.restore()
        c4.advance(0.1)
        precondition(!restarting.hidden)
        t4.hide(targets: [restarting.target])
        c4.advance(2)
        precondition(restarting.hidden, "A new hide must cancel stale restore retries")

        let c5 = Clock(), t5 = c5.toggle(), first = App(50), second = App(51)
        t5.hide(targets: [first.target, second.target])
        precondition(t5.shouldRestore(hasVisibleWindows: true), "A quick second press cancels the hide")
        c5.advance(2)
        first.hidden = false // The user manually reopens one App.
        t5.synchronize()
        precondition(!t5.shouldRestore(hasVisibleWindows: true),
                     "An open window must be hidden rather than restoring all other Apps")
        t5.hide(targets: [first.target, second.target])
        c5.advance(4)
        precondition(first.hidden && second.hidden && t5.hiddenPIDs == [50, 51])
        precondition(t5.shouldRestore(hasVisibleWindows: false))
        t5.restore()
        c5.advance(5)
        precondition(!first.hidden && !second.hidden, "Both batches must restore together")
        print("APPLICATION_VISIBILITY_OK async-retry bounded-failure restore-cancels-retry personal-state-preserved")
    }
}
