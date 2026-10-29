import Foundation

@main struct LaunchAtLoginSelfTest {
    enum Failure: Error { case denied }
    static func main() {
        var systemState = LaunchAtLoginSettings.State.disabled
        var fail = false
        var registered = 0
        var unregistered = 0
        var opened = 0
        let settings = LaunchAtLoginSettings(backend: .init(read: { systemState }, register: {
            registered += 1
            if fail { throw Failure.denied }
            systemState = .enabled
        }, unregister: {
            unregistered += 1
            if fail { throw Failure.denied }
            systemState = .disabled
        }, openSettings: { opened += 1 }))
        precondition(!settings.isOn)
        settings.setEnabled(true)
        precondition(settings.isOn && registered == 1)
        settings.setEnabled(true)
        precondition(registered == 1)
        fail = true
        settings.setEnabled(false)
        precondition(settings.isOn && settings.errorMessage != nil)
        fail = false
        settings.setEnabled(false)
        precondition(!settings.isOn && settings.errorMessage == nil && unregistered == 2)
        systemState = .requiresApproval
        settings.refresh()
        precondition(settings.isOn)
        settings.setEnabled(true)
        precondition(opened == 1 && registered == 1)
        settings.setEnabled(false)
        precondition(!settings.isOn)
        systemState = .enabled // A change made in System Settings must be reflected.
        settings.refresh()
        precondition(settings.isOn)
        print("LAUNCH_AT_LOGIN_OK system-state error-rollback approval unregister external-refresh")
    }
}
