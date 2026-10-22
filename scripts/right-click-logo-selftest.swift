import AppKit

@main
@MainActor
struct RightClickLogoSelfTest {
    static func main() {
        _ = NSApplication.shared
        let view = EasterEggLogoView(frame: NSRect(x: 0, y: 0, width: 64, height: 64))
        var unlocks = 0
        view.onUnlock = { unlocks += 1 }
        func arm() {
            let click = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero,
                                          modifierFlags: [], timestamp: 0, windowNumber: 0,
                                          context: nil, eventNumber: 1, clickCount: 2, pressure: 1)!
            view.mouseDown(with: click)
        }
        func key(_ code: UInt16, down: Bool, at time: Double) {
            let event = NSEvent.keyEvent(with: down ? .keyDown : .keyUp, location: .zero,
                                        modifierFlags: [], timestamp: time, windowNumber: 0,
                                        context: nil, characters: "", charactersIgnoringModifiers: "",
                                        isARepeat: false, keyCode: code)!
            if down { view.keyDown(with: event) } else { view.keyUp(with: event) }
        }
        func prefix() {
            for (index, code) in [UInt16(1), 2, 1, 0, 38, 1, 2, 1, 2].enumerated() {
                key(code, down: true, at: Double(index) * 0.2)
                key(code, down: false, at: Double(index) * 0.2 + 0.05)
            }
        }
        arm()
        prefix()
        key(38, down: true, at: 2)
        key(37, down: true, at: 2.08)
        precondition(unlocks == 1, "Focused-logo key handlers must deliver the unlock callback")
        arm()
        prefix()
        key(38, down: true, at: 2)
        key(38, down: false, at: 2.04)
        key(37, down: true, at: 2.08)
        precondition(unlocks == 1, "Sequential final letters must not unlock")
        view.stop()
        print("RIGHT_CLICK_LOGO_OK double_click responder_keys unlock_callback sequential_chord_rejected")
    }
}
