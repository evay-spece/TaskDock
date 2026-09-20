import ApplicationServices

final class AccessibilityPermissionService {
    var isTrusted: Bool { AXIsProcessTrusted() }

    func requestAccess() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
}
