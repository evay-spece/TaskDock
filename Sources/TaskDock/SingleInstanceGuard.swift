import AppKit
import Darwin

enum SingleInstanceGuard {
    private static var lockDescriptor: Int32 = -1

    static func acquireOrActivateExisting() -> Bool {
        let path = "/tmp/com.taskdock.app.\(getuid()).lock"
        let descriptor = open(path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { return false }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            let ownPID = ProcessInfo.processInfo.processIdentifier
            NSWorkspace.shared.runningApplications
                .first { $0.bundleIdentifier == "com.taskdock.app" && $0.processIdentifier != ownPID }?
                .activate(options: [.activateIgnoringOtherApps])
            return false
        }
        lockDescriptor = descriptor
        return true
    }
}
