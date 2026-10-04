import AppKit
import Carbon

/// Keeps Option shortcuts registered while the taskbar is visible.
@MainActor
final class OptionWindowHotKeyMonitor {
    static let windowShortcutLabels = ["J", "K", "L", ";", "'", "N", "M", ",", "."]
    static let favoriteShortcutLabels = (1...9).map(String.init)

    enum Target: Equatable {
        case window(Int)
        case favorite(Int)
    }

    struct Registered: Equatable {
        var windows: Set<Int> = []
        var favorites: Set<Int> = []
    }

    private let signature: OSType = 0x54444F43 // TDOC
    private let onShortcut: (Target) -> Void
    private var eventHandler: EventHandlerRef?
    private var hotKeys: [UInt32: EventHotKeyRef] = [:]

    init(onShortcut: @escaping (Target) -> Void) {
        self.onShortcut = onShortcut
    }

    func start(windowCount: Int, favoriteCount: Int) -> Registered {
        stop()
        guard windowCount > 0 || favoriteCount > 0 else { return Registered() }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
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
                guard result == noErr, hotKeyID.signature == 0x54444F43 else {
                    return OSStatus(eventNotHandledErr)
                }
                let monitor = Unmanaged<OptionWindowHotKeyMonitor>
                    .fromOpaque(userData).takeUnretainedValue()
                let hotKeyIDValue = hotKeyID.id
                Task { @MainActor in
                    guard monitor.hotKeys[hotKeyIDValue] != nil else { return }
                    if hotKeyIDValue >= 101 {
                        monitor.onShortcut(.favorite(Int(hotKeyIDValue - 100)))
                    } else {
                        monitor.onShortcut(.window(Int(hotKeyIDValue)))
                    }
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard status == noErr else { return Registered() }

        let windowKeyCodes = [
            kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L, kVK_ANSI_Semicolon,
            kVK_ANSI_Quote, kVK_ANSI_N, kVK_ANSI_M, kVK_ANSI_Comma, kVK_ANSI_Period
        ]
            .map(UInt32.init)
        let favoriteKeyCodes = [
            kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
            kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9
        ]
            .map(UInt32.init)
        var registered = Registered()
        if windowCount > 0 {
            for index in 1...min(windowCount, windowKeyCodes.count) {
                if register(windowKeyCodes[index - 1], id: UInt32(index)) {
                    registered.windows.insert(index)
                }
            }
        }
        if favoriteCount > 0 {
            for index in 1...min(favoriteCount, favoriteKeyCodes.count) {
                if register(favoriteKeyCodes[index - 1], id: UInt32(100 + index)) {
                    registered.favorites.insert(index)
                }
            }
        }
        if hotKeys.isEmpty { stop() }
        return registered
    }

    private func register(_ keyCode: UInt32, id: UInt32) -> Bool {
        var hotKey: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        if RegisterEventHotKey(
            keyCode, UInt32(optionKey), hotKeyID,
            GetApplicationEventTarget(), 0, &hotKey
        ) == noErr, let hotKey {
            hotKeys[id] = hotKey
            return true
        }
        return false
    }

    func stop() {
        for hotKey in hotKeys.values { UnregisterEventHotKey(hotKey) }
        hotKeys.removeAll()
        if let eventHandler { RemoveEventHandler(eventHandler) }
        eventHandler = nil
    }
}
