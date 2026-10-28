import Carbon
import AppKit

/// Keeps Option+D available even when TaskDock is hidden or another layout is selected.
@MainActor
final class GlobalMinimizeHotKeyMonitor {
    private let signature: OSType = 0x54444D4E // TDMN
    private let onTrigger: () -> Void
    private var eventHandler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private var isPressed = false
    private var releaseTimer: Timer?

    init(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
    }

    @discardableResult
    func start() -> Bool {
        stop()
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID(signature: 0, id: 0)
                let result = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard result == noErr, hotKeyID.signature == 0x54444D4E, hotKeyID.id == 1 else {
                    return OSStatus(eventNotHandledErr)
                }
                let monitor = Unmanaged<GlobalMinimizeHotKeyMonitor>
                    .fromOpaque(userData).takeUnretainedValue()
                let kind = GetEventKind(event)
                Task { @MainActor in monitor.handle(kind: kind) }
                return noErr
            },
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard status == noErr else { return false }

        var registeredHotKey: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: 1)
        guard RegisterEventHotKey(
            UInt32(kVK_ANSI_D), UInt32(optionKey), hotKeyID,
            GetApplicationEventTarget(), 0, &registeredHotKey
        ) == noErr, let registeredHotKey else {
            stop()
            return false
        }
        hotKey = registeredHotKey
        return true
    }

    private func handle(kind: UInt32) {
        guard hotKey != nil else { return }
        if kind == UInt32(kEventHotKeyReleased) {
            isPressed = false
            releaseTimer?.invalidate()
            releaseTimer = nil
        } else if kind == UInt32(kEventHotKeyPressed), !isPressed {
            isPressed = true
            releaseTimer?.invalidate()
            let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    // Carbon can miss release when Option is released before D.
                    if !CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_ANSI_D)) {
                        self.isPressed = false
                        self.releaseTimer?.invalidate()
                        self.releaseTimer = nil
                    }
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            releaseTimer = timer
            onTrigger()
        }
    }

    func stop() {
        releaseTimer?.invalidate()
        releaseTimer = nil
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        if let eventHandler { RemoveEventHandler(eventHandler) }
        eventHandler = nil
        isPressed = false
    }
}
