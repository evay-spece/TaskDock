import AppKit
import Carbon

@main
@MainActor
struct OptionShortcutSelfTest {
    static func main() {
        _ = NSApplication.shared
        var selected: [OptionWindowHotKeyMonitor.Target] = []
        let monitor = OptionWindowHotKeyMonitor { selected.append($0) }
        precondition(OptionWindowHotKeyMonitor.windowShortcutLabels ==
            ["J", "K", "L", ";", "'", "N", "M", ",", "."])
        let registered = monitor.start(windowCount: 9, favoriteCount: 9)
        precondition(registered.windows == Set(1...9), "Window shortcuts failed: \(registered)")
        precondition(registered.favorites == Set(1...9), "Favorite shortcuts failed: \(registered)")
        for id in Array(1...9) + Array(101...109) {
            sendHotKey(id: id)
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let expected = (1...9).map(OptionWindowHotKeyMonitor.Target.window)
            + (1...9).map(OptionWindowHotKeyMonitor.Target.favorite)
        precondition(selected == expected, "Unexpected shortcut dispatch: \(selected)")

        let favoritesOnly = monitor.start(windowCount: 0, favoriteCount: 9)
        precondition(favoritesOnly.windows.isEmpty && favoritesOnly.favorites == Set(1...9))
        let windowsOnly = monitor.start(windowCount: 9, favoriteCount: 0)
        precondition(windowsOnly.windows == Set(1...9) && windowsOnly.favorites.isEmpty)
        let companion = monitor.start(windowCount: 5, favoriteCount: 8)
        precondition(companion.windows == Set(1...5) && companion.favorites == Set(1...8))
        monitor.stop()
        print("OPTION_WINDOW_AND_FAVORITE_SHORTCUTS_OK")
    }

    private static func sendHotKey(id: Int) {
        var event: EventRef?
        precondition(CreateEvent(
            nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed),
            0, 0, &event
        ) == noErr)
        var hotKeyID = EventHotKeyID(signature: 0x54444F43, id: UInt32(id))
        precondition(SetEventParameter(
            event!, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
            MemoryLayout<EventHotKeyID>.size, &hotKeyID
        ) == noErr)
        precondition(SendEventToEventTarget(event!, GetApplicationEventTarget()) == noErr)
        ReleaseEvent(event!)
    }
}
