import Foundation

@main
struct RightClickEasterEggSelfTest {
    static let prefix: [UInt16] = [1, 2, 1, 0, 38, 1, 2, 1, 2]

    static func enterPrefix(_ sequence: inout RightClickEasterEggSequence, startingAt start: Double = 0) {
        for (index, key) in prefix.enumerated() {
            let at = start + Double(index) * 0.2
            precondition(sequence.handle(keyCode: key, isDown: true, at: at) == .flash)
            precondition(sequence.handle(keyCode: key, isDown: false, at: at + 0.05) == .ignored)
        }
        precondition(sequence.progress == prefix.count)
    }

    static func main() {
        var sequence = RightClickEasterEggSequence()
        precondition(sequence.handle(keyCode: 1, isDown: true, at: 0) == .ignored)
        sequence.arm()
        enterPrefix(&sequence)
        precondition(sequence.handle(keyCode: 38, isDown: true, at: 2) == .flash)
        precondition(sequence.handle(keyCode: 37, isDown: true, at: 2.08) == .unlocked)
        precondition(!sequence.isArmed)

        // A simultaneous chord accepts either physical key-down order.
        sequence.arm()
        enterPrefix(&sequence)
        precondition(sequence.handle(keyCode: 37, isDown: true, at: 2) == .flash)
        precondition(sequence.handle(keyCode: 38, isDown: true, at: 2.1) == .unlocked)

        // Typing J then L with a release between them must not unlock.
        sequence.arm()
        enterPrefix(&sequence)
        _ = sequence.handle(keyCode: 38, isDown: true, at: 2)
        _ = sequence.handle(keyCode: 38, isDown: false, at: 2.05)
        precondition(sequence.handle(keyCode: 37, isDown: true, at: 2.1) == .flash)
        precondition(sequence.isArmed && sequence.progress == 0)

        sequence.arm()
        enterPrefix(&sequence)
        _ = sequence.handle(keyCode: 38, isDown: true, at: 2)
        precondition(sequence.handle(keyCode: 37, isDown: true, at: 2.4) == .flash)
        precondition(sequence.progress == 0)

        // Repeats, incorrect keys, modified shortcuts, and old attempts cannot advance.
        sequence.arm()
        _ = sequence.handle(keyCode: 1, isDown: true, at: 0)
        precondition(sequence.handle(keyCode: 1, isDown: true, isRepeat: true, at: 0.1) == .ignored)
        precondition(sequence.progress == 1)
        _ = sequence.handle(keyCode: 12, isDown: true, at: 0.2)
        precondition(sequence.progress == 0)
        sequence.arm()
        _ = sequence.handle(keyCode: 1, isDown: true, hasModifiers: true, at: 0)
        precondition(sequence.progress == 0)
        sequence.arm()
        _ = sequence.handle(keyCode: 1, isDown: true, at: 0)
        _ = sequence.handle(keyCode: 1, isDown: false, at: 0.1)
        _ = sequence.handle(keyCode: 2, isDown: true, at: 11)
        precondition(sequence.progress == 0)
        sequence.reset()
        precondition(!sequence.isArmed && sequence.progress == 0)
        print("RIGHT_CLICK_EASTER_EGG_OK prefix overlapping_chord reverse_chord sequential_rejected timeout_repeat_modifier_reset")
    }
}
