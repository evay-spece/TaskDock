import AppKit

/// Keeps an app-level snapshot so showing the desktop never changes AXMinimized.
final class ApplicationVisibilityToggle {
    private var hiddenApplications: [NSRunningApplication] = []
    private var previousFrontmost: NSRunningApplication?
    private var requestedAt = Date.distantPast

    var canRestore: Bool { !hiddenApplications.isEmpty }
    var hiddenPIDs: Set<pid_t> { Set(hiddenApplications.filter { !$0.isTerminated }.map(\.processIdentifier)) }

    func synchronize() {
        hiddenApplications = hiddenApplications.filter {
            !$0.isTerminated && ($0.isHidden || Date().timeIntervalSince(requestedAt) < 0.5)
        }
        if hiddenApplications.isEmpty { previousFrontmost = nil }
    }

    func hide(applications: [NSRunningApplication] = NSWorkspace.shared.runningApplications,
              frontmost: NSRunningApplication? = NSWorkspace.shared.frontmostApplication) {
        guard hiddenApplications.isEmpty else { return }
        requestedAt = Date()
        hiddenApplications = applications.filter { app in
            guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  app.activationPolicy == .regular, !app.isHidden, !app.isTerminated else { return false }
            // hide() may report false even when the asynchronous request takes effect.
            // Record the initially visible app, then reconcile against isHidden.
            _ = app.hide()
            return true
        }
        if let frontmost, hiddenApplications.contains(where: { $0 == frontmost }) {
            previousFrontmost = frontmost
        }
    }

    func restore() {
        let applications = hiddenApplications
        for app in applications where !app.isTerminated { _ = app.unhide() }
        if let frontmost = previousFrontmost, !frontmost.isTerminated,
           applications.contains(where: { $0 == frontmost }) {
            _ = frontmost.activate(options: [.activateIgnoringOtherApps])
        }
        hiddenApplications = []
        previousFrontmost = nil
    }
}
