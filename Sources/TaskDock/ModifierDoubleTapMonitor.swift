import AppKit

@MainActor
final class ModifierDoubleTapMonitor {
    private let settings: SettingsStore
    private let onDoubleTap: () -> Void
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var lastTapAt: Date?
    private var modifierIsDown = false

    init(settings: SettingsStore, onDoubleTap: @escaping () -> Void) {
        self.settings = settings
        self.onDoubleTap = onDoubleTap
    }

    func start() {
        stop()
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        lastTapAt = nil
        modifierIsDown = false
    }

    private func handle(_ event: NSEvent) {
        if event.type == .keyDown {
            lastTapAt = nil
            return
        }

        let desiredFlag = modifierFlag
        let relevantFlags = event.modifierFlags.intersection([.option, .command, .control, .shift])
        let desiredIsDown = relevantFlags.contains(desiredFlag)

        if desiredIsDown, !modifierIsDown, relevantFlags == desiredFlag {
            let now = Date()
            if let lastTapAt, now.timeIntervalSince(lastTapAt) <= 0.38 {
                self.lastTapAt = nil
                onDoubleTap()
            } else {
                lastTapAt = now
            }
        }
        modifierIsDown = desiredIsDown
    }

    private var modifierFlag: NSEvent.ModifierFlags {
        switch settings.toggleModifier {
        case .option: return .option
        case .command: return .command
        case .control: return .control
        }
    }
}
