import AppKit
import Carbon
import SwiftUI

enum MinimizeShortcutSettings {
    static let keyCodeKey = "taskdock.minimizeShortcutKeyCodeV1"
    static let modifiersKey = "taskdock.minimizeShortcutModifiersV1"
    static let characterKey = "taskdock.minimizeShortcutCharacterV1"
    static let defaultKeyCode = UInt32(kVK_ANSI_D)
    static let defaultModifiers = UInt32(optionKey)

    static func current(defaults: UserDefaults = .standard) -> (keyCode: UInt32, modifiers: UInt32, character: String) {
        let code = defaults.object(forKey: keyCodeKey) as? Int ?? Int(defaultKeyCode)
        let flags = defaults.object(forKey: modifiersKey) as? Int ?? Int(defaultModifiers)
        let character = defaults.string(forKey: characterKey) ?? "d"
        return (UInt32(max(0, code)), UInt32(max(0, flags)), character)
    }

    static func carbonModifiers(for flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    static func label(modifiers: UInt32, character: String) -> String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result + character.uppercased()
    }

    static func menuModifiers(_ modifiers: UInt32) -> NSEvent.ModifierFlags {
        var result: NSEvent.ModifierFlags = []
        if modifiers & UInt32(optionKey) != 0 { result.insert(.option) }
        if modifiers & UInt32(cmdKey) != 0 { result.insert(.command) }
        if modifiers & UInt32(controlKey) != 0 { result.insert(.control) }
        if modifiers & UInt32(shiftKey) != 0 { result.insert(.shift) }
        return result
    }

    static func conflictsWithTaskbarShortcut(keyCode: UInt16, modifiers: UInt32) -> Bool {
        guard modifiers == UInt32(optionKey) else { return false }
        let reserved = Set([
            kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L, kVK_ANSI_Semicolon,
            kVK_ANSI_Quote, kVK_ANSI_N, kVK_ANSI_M, kVK_ANSI_Comma,
            kVK_ANSI_Period, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3,
            kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7,
            kVK_ANSI_8, kVK_ANSI_9
        ].map(UInt16.init))
        return reserved.contains(keyCode)
    }
}

final class ShortcutCaptureButton: NSButton {
    var onCapture: ((Int, Int, String) -> Void)?
    private var recording = false
    private var previousTitle = ""

    override var acceptsFirstResponder: Bool { true }

    @objc func beginRecording() {
        recording = true
        previousTitle = title
        title = "请按新快捷键…"
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == UInt16(kVK_Escape) {
            recording = false
            title = previousTitle
            return
        }
        let modifiers = MinimizeShortcutSettings.carbonModifiers(for: event.modifierFlags)
        guard modifiers & (UInt32(optionKey) | UInt32(cmdKey) | UInt32(controlKey)) != 0,
              let character = event.charactersIgnoringModifiers,
              !character.isEmpty else {
            NSSound.beep()
            return
        }
        guard !MinimizeShortcutSettings.conflictsWithTaskbarShortcut(
            keyCode: event.keyCode, modifiers: modifiers
        ) else {
            NSSound.beep()
            return
        }
        recording = false
        onCapture?(Int(event.keyCode), Int(modifiers), String(character.prefix(1)).lowercased())
    }
}

struct MinimizeShortcutRecorder: NSViewRepresentable {
    @Binding var keyCode: Int
    @Binding var modifiers: Int
    @Binding var character: String

    func makeNSView(context: Context) -> ShortcutCaptureButton {
        let button = ShortcutCaptureButton()
        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)
        button.target = button
        button.action = #selector(ShortcutCaptureButton.beginRecording)
        return button
    }

    func updateNSView(_ button: ShortcutCaptureButton, context: Context) {
        button.title = MinimizeShortcutSettings.label(modifiers: UInt32(modifiers), character: character)
        button.onCapture = { code, flags, key in
            keyCode = code
            modifiers = flags
            character = key
        }
        button.setAccessibilityLabel("录制最小化全部窗口快捷键")
    }
}
