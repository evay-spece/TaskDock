import AppKit
import Carbon

final class FinderCutHotkey {
    private var handler: EventHandlerRef?
    private var cutHotkey: EventHotKeyRef?
    private var pasteHotkey: EventHotKeyRef?
    private var observer: NSObjectProtocol?
    private var timer: Timer?

    func start() {
        var kind = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<FinderCutHotkey>.fromOpaque(context).takeUnretainedValue()
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event, UInt32(kEventParamDirectObject), UInt32(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard status == noErr else { return OSStatus(eventNotHandledErr) }
            if identifier.signature == 0x4E464358, identifier.id == 1 {
                DispatchQueue.main.async { owner.cutFinderSelection() }
                return noErr
            }
            if identifier.signature == 0x4E464356, identifier.id == 2 {
                DispatchQueue.main.async { owner.pasteAndMove() }
                return noErr
            }
            return OSStatus(eventNotHandledErr)
        }, 1, &kind, context, &handler)
        UserDefaults.standard.set("handler \(installStatus)", forKey: "hotkeyStatus")
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.updateRegistration() }
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in self?.updateRegistration() }
        updateRegistration()
    }

    private func updateRegistration() {
        let finderIsActive = finderAcceptsFileShortcuts()
        if finderIsActive && cutHotkey == nil {
            let id = EventHotKeyID(signature: 0x4E464358, id: 1)
            let status = RegisterEventHotKey(UInt32(kVK_ANSI_X), UInt32(cmdKey), id,
                                             GetApplicationEventTarget(), 0, &cutHotkey)
            UserDefaults.standard.set("registered \(status)", forKey: "hotkeyStatus")
        } else if !finderIsActive, let cutHotkey {
            UnregisterEventHotKey(cutHotkey)
            self.cutHotkey = nil
        }
        let shouldHandlePaste = finderIsActive && !ClipboardCutter.cutFiles().isEmpty
        if shouldHandlePaste && pasteHotkey == nil {
            let id = EventHotKeyID(signature: 0x4E464356, id: 2)
            let status = RegisterEventHotKey(UInt32(kVK_ANSI_V), UInt32(cmdKey), id,
                                             GetApplicationEventTarget(), 0, &pasteHotkey)
            UserDefaults.standard.set("paste registered \(status)", forKey: "pasteHotkeyStatus")
        } else if !shouldHandlePaste, let pasteHotkey {
            UnregisterEventHotKey(pasteHotkey)
            self.pasteHotkey = nil
        }
    }

    private func cutFinderSelection() {
        guard finderAcceptsFileShortcuts() else { return }
        readFinderSelection()
        updateRegistration()
    }

    private func pasteAndMove() {
        guard finderAcceptsFileShortcuts() else { return }
        let script = """
            tell application id "com.apple.finder"
                if (count of Finder windows) > 0 then
                    return POSIX path of (target of front Finder window as alias)
                else
                    return POSIX path of (desktop as alias)
                end if
            end tell
            """
        var error: NSDictionary?
        guard let path = NSAppleScript(source: script)?.executeAndReturnError(&error).stringValue else {
            UserDefaults.standard.set("destination error \(error?["NSAppleScriptErrorNumber"] ?? "unknown")", forKey: "pasteHotkeyStatus")
            NSSound.beep()
            return
        }
        do {
            let targets = try ClipboardCutter.move(to: URL(fileURLWithPath: path, isDirectory: true))
            UserDefaults.standard.set("moved \(targets.count)", forKey: "pasteHotkeyStatus")
            NSWorkspace.shared.activateFileViewerSelecting(targets)
        } catch {
            UserDefaults.standard.set("move error \(error.localizedDescription)", forKey: "pasteHotkeyStatus")
            let alert = NSAlert()
            alert.messageText = "无法粘贴并移动"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        updateRegistration()
    }

    // Finder uses the same shortcuts while editing a name, path, or search query.
    // Let those text controls handle their own cut and paste commands.
    private func finderAcceptsFileShortcuts() -> Bool {
        guard FileTypeSettings.isEnabled,
              let application = NSWorkspace.shared.frontmostApplication,
              application.bundleIdentifier == "com.apple.finder" else { return false }
        let element = AXUIElementCreateApplication(application.processIdentifier)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused else { return false }
        var role: CFTypeRef?
        let focusedElement = focused as! AXUIElement
        guard AXUIElementCopyAttributeValue(focusedElement, kAXRoleAttribute as CFString, &role) == .success,
              let role = role as? String else { return false }
        return ![kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role)
    }

    func testFinderSelection() -> String {
        guard FileTypeSettings.isEnabled else { return "右键功能未开启" }
        readFinderSelection()
        updateRegistration()
        return UserDefaults.standard.string(forKey: "hotkeyStatus") ?? "未取得结果"
    }

    private func readFinderSelection() {
        let script = """
            tell application id "com.apple.finder"
                set selectedPaths to {}
                repeat with selectedItem in (get selection)
                    set end of selectedPaths to POSIX path of (selectedItem as alias)
                end repeat
                return selectedPaths
            end tell
            """
        var error: NSDictionary?
        guard let result = NSAppleScript(source: script)?.executeAndReturnError(&error) else {
            UserDefaults.standard.set("script error \(error?["NSAppleScriptErrorNumber"] ?? "unknown")", forKey: "hotkeyStatus")
            NSSound.beep()
            return
        }
        guard result.numberOfItems > 0 else {
            UserDefaults.standard.set("no selection", forKey: "hotkeyStatus")
            NSSound.beep()
            return
        }
        let paths = (1...result.numberOfItems).compactMap { result.atIndex($0)?.stringValue }
        let success = ClipboardCutter.cut(paths.map { URL(fileURLWithPath: $0) })
        UserDefaults.standard.set("items \(paths.count), copied \(success)", forKey: "hotkeyStatus")
        guard success else { NSSound.beep(); return }
    }
}
