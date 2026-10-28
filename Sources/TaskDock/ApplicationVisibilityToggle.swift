import AppKit

/// Keeps an app-level snapshot so showing the desktop never changes AXMinimized.
@MainActor
final class ApplicationVisibilityToggle {
    struct Target {
        let pid: pid_t
        let isHidden: () -> Bool
        let isTerminated: () -> Bool
        let hide: () -> Void
        let unhide: () -> Void
    }

    private var hiddenApplications: [Target] = []
    private var restoreFrontmost: (() -> Void)?
    private var generation = 0
    private var hideSettlesAt: TimeInterval = 0
    private let now: () -> TimeInterval
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void

    init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, action in
             DispatchQueue.main.asyncAfter(deadline: .now() + delay) { action() }
         }) {
        self.now = now
        self.schedule = schedule
    }

    var canRestore: Bool { !hiddenApplications.isEmpty }
    func shouldRestore(hasVisibleWindows: Bool) -> Bool {
        canRestore && (now() < hideSettlesAt || !hasVisibleWindows)
    }
    var hiddenPIDs: Set<pid_t> {
        Set(hiddenApplications.filter { !$0.isTerminated() }.map(\.pid))
    }

    func synchronize() {
        hiddenApplications = hiddenApplications.filter {
            !$0.isTerminated() && ($0.isHidden() || now() < hideSettlesAt)
        }
        if hiddenApplications.isEmpty { restoreFrontmost = nil }
    }

    func hide(applications: [NSRunningApplication] = NSWorkspace.shared.runningApplications,
              frontmost: NSRunningApplication? = NSWorkspace.shared.frontmostApplication) {
        let visible = applications.filter {
            $0.processIdentifier != ProcessInfo.processInfo.processIdentifier &&
                $0.activationPolicy == .regular && !$0.isHidden && !$0.isTerminated
        }
        // Hide the frontmost app last, avoiding focus changes mid-batch.
        let ordered = visible.filter { $0 != frontmost } + visible.filter { $0 == frontmost }
        let targets = ordered.map { app in
            Target(pid: app.processIdentifier, isHidden: { app.isHidden },
                   isTerminated: { app.isTerminated }, hide: { _ = app.hide() },
                   unhide: { _ = app.unhide() })
        }
        let restoreFocus: (() -> Void)? = frontmost.flatMap { app in
            guard visible.contains(app) else { return nil }
            return { if !app.isTerminated { _ = app.activate(options: [.activateIgnoringOtherApps]) } }
        }
        hide(targets: targets, restoreFocus: restoreFocus)
    }

    func hide(targets: [Target], restoreFocus: (() -> Void)? = nil) {
        generation += 1
        let operation = generation
        hideSettlesAt = now() + 1.15
        let existingPIDs = hiddenPIDs
        hiddenApplications += targets.filter {
            !existingPIDs.contains($0.pid) && !$0.isTerminated() && !$0.isHidden()
        }
        restoreFrontmost = restoreFocus
        for target in hiddenApplications { target.hide() }
        // AppKit requests are asynchronous. Verify state instead of trusting hide()'s return value.
        for delay in [0.08, 0.22, 0.5, 0.9] {
            schedule(delay) { [weak self] in
                guard let self, self.generation == operation else { return }
                for target in self.hiddenApplications where !target.isTerminated() && !target.isHidden() {
                    target.hide()
                }
            }
        }
        schedule(1.16) { [weak self] in
            guard let self, self.generation == operation else { return }
            self.synchronize()
        }
    }

    func restore() {
        generation += 1 // Cancels all pending hide retries before any window is restored.
        let operation = generation
        let applications = hiddenApplications
        let focus = restoreFrontmost
        hiddenApplications = []
        restoreFrontmost = nil
        for target in applications where !target.isTerminated() { target.unhide() }
        focus?()
        for delay in [0.08, 0.22, 0.5] {
            schedule(delay) { [weak self] in
                guard self?.generation == operation else { return }
                for target in applications where !target.isTerminated() && target.isHidden() {
                    target.unhide()
                }
            }
        }
    }
}
