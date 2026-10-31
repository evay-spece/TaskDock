import Foundation

@main
@MainActor
struct SystemDockVisibilitySelfTest {
    static func main() {
        testHiddenVisibleExit()
        testVisibleAtLaunchAndControllerRestart()
        testOriginallyUnsetPreferences()
        testTemporaryTaskbarHideAndReturn()
        testExpiredAccessAndReactivation()
        testNativeReservation()
        testReservationAbsentKeysAndCrashRecovery()
        print("DOCK_VISIBILITY_OK reservation-switch restore crash calibration access")
    }

    private static func testHiddenVisibleExit() {
        let (domain, dock, task, cleanup) = testDefaults()
        defer { cleanup() }
        dock.set(false, forKey: "autohide")
        var restarts = 0
        let controller = SystemDockVisibilityController(
            domain: domain,
            dockDefaults: dock,
            snapshotDefaults: task,
            restartDock: { restarts += 1 }
        )

        controller.synchronize(hidden: true)
        precondition(dock.bool(forKey: "autohide"))
        precondition(dock.double(forKey: "autohide-delay") == 1000)
        precondition(task.dictionary(forKey: "taskdock.originalSystemDockPreferences") != nil)
        controller.synchronize(hidden: true)
        precondition(restarts == 1)

        controller.synchronize(hidden: false)
        precondition(!dock.bool(forKey: "autohide"))
        precondition(dock.object(forKey: "autohide-delay") == nil)
        precondition(task.dictionary(forKey: "taskdock.originalSystemDockPreferences") != nil)
        controller.synchronize(hidden: false)
        precondition(restarts == 2)

        controller.restore()
        precondition(!dock.bool(forKey: "autohide"))
        precondition(dock.object(forKey: "autohide-delay") == nil)
        precondition(task.dictionary(forKey: "taskdock.originalSystemDockPreferences") == nil)
        precondition(restarts == 2)
    }

    private static func testVisibleAtLaunchAndControllerRestart() {
        let (domain, dock, task, cleanup) = testDefaults()
        defer { cleanup() }
        dock.set(true, forKey: "autohide")
        dock.set(0.25, forKey: "autohide-delay")
        var restarts = 0
        let firstController = SystemDockVisibilityController(
            domain: domain,
            dockDefaults: dock,
            snapshotDefaults: task,
            restartDock: { restarts += 1 }
        )
        firstController.synchronize(hidden: false)
        precondition(!dock.bool(forKey: "autohide"))
        precondition(dock.object(forKey: "autohide-delay") == nil)

        let restartedController = SystemDockVisibilityController(
            domain: domain,
            dockDefaults: dock,
            snapshotDefaults: task,
            restartDock: { restarts += 1 }
        )
        restartedController.synchronize(hidden: true)
        precondition(dock.bool(forKey: "autohide"))
        precondition(dock.double(forKey: "autohide-delay") == 1000)
        restartedController.synchronize(hidden: false)
        restartedController.restore()
        precondition(dock.bool(forKey: "autohide"))
        precondition(dock.double(forKey: "autohide-delay") == 0.25)
        precondition(task.dictionary(forKey: "taskdock.originalSystemDockPreferences") == nil)
        precondition(restarts == 4)
    }

    private static func testOriginallyUnsetPreferences() {
        let (domain, dock, task, cleanup) = testDefaults()
        defer { cleanup() }
        var restarts = 0
        let controller = SystemDockVisibilityController(
            domain: domain,
            dockDefaults: dock,
            snapshotDefaults: task,
            restartDock: { restarts += 1 }
        )
        controller.synchronize(hidden: false)
        precondition(dock.object(forKey: "autohide") as? Bool == false)
        precondition(dock.object(forKey: "autohide-delay") == nil)
        controller.restore()
        precondition(dock.object(forKey: "autohide") == nil)
        precondition(dock.object(forKey: "autohide-delay") == nil)
        precondition(restarts == 2)
    }

    private static func testTemporaryTaskbarHideAndReturn() {
        let (domain, dock, task, cleanup) = testDefaults()
        defer { cleanup() }
        dock.set(true, forKey: "autohide")
        dock.set(0.25, forKey: "autohide-delay")
        var restarts = 0
        let controller = SystemDockVisibilityController(
            domain: domain,
            dockDefaults: dock,
            snapshotDefaults: task,
            restartDock: { restarts += 1 }
        )

        controller.synchronize(hidden: true)
        precondition(dock.double(forKey: "autohide-delay") == 1000)
        controller.restore() // Taskbar is temporarily hidden.
        precondition(dock.bool(forKey: "autohide"))
        precondition(dock.double(forKey: "autohide-delay") == 0.25)
        precondition(task.dictionary(forKey: "taskdock.originalSystemDockPreferences") == nil)

        controller.synchronize(hidden: true) // Taskbar comes back.
        precondition(dock.double(forKey: "autohide-delay") == 1000)
        controller.restore()
        precondition(dock.double(forKey: "autohide-delay") == 0.25)
        precondition(restarts == 4)
    }

    private static func testExpiredAccessAndReactivation() {
        let (domain, dock, task, cleanup) = testDefaults()
        defer { cleanup() }
        dock.set(true, forKey: "autohide")
        dock.set(0.25, forKey: "autohide-delay")
        var restarts = 0
        let controller = SystemDockVisibilityController(
            domain: domain, dockDefaults: dock, snapshotDefaults: task,
            restartDock: { restarts += 1 })
        controller.synchronize(hidden: true, accessAllowed: true)
        precondition(dock.double(forKey: "autohide-delay") == 1000)
        controller.synchronize(hidden: true, accessAllowed: false)
        precondition(dock.bool(forKey: "autohide"))
        precondition(dock.double(forKey: "autohide-delay") == 0.25)
        precondition(task.dictionary(forKey: "taskdock.originalSystemDockPreferences") == nil)
        controller.synchronize(hidden: false, accessAllowed: false)
        precondition(restarts == 2, "Locked modes must not overwrite the restored preferences")
        controller.synchronize(hidden: true, accessAllowed: true)
        precondition(dock.double(forKey: "autohide-delay") == 1000)
        controller.restore()
        precondition(dock.double(forKey: "autohide-delay") == 0.25)
        precondition(restarts == 4)
    }

    private static func testNativeReservation() {
        let (domain, dock, task, cleanup) = testDefaults()
        defer { cleanup() }
        let original: [String: Any] = ["autohide": true, "autohide-delay": 0.4,
            "orientation": "left", "tilesize": 72.0, "magnification": true,
            "launchanim": true, "no-bouncing": false, "persistent-apps": ["keep-me"]]
        dock.setPersistentDomain(original, forName: domain)
        var restarts = 0
        let controller = SystemDockVisibilityController(domain: domain, dockDefaults: dock,
            snapshotDefaults: task, restartDock: { restarts += 1 })
        controller.synchronize(hidden: true)
        let start = Date()
        controller.synchronizeReservation(height: 60, now: start)
        precondition(!dock.bool(forKey: "autohide"))
        precondition(dock.string(forKey: "orientation") == "bottom")
        precondition(!dock.bool(forKey: "magnification"))
        precondition(dock.double(forKey: "tilesize") == 44)
        controller.synchronizeReservation(height: 60, measuredInset: 70, now: start.addingTimeInterval(1))
        precondition(dock.double(forKey: "tilesize") == 44, "Calibrated before Dock settled")
        controller.synchronizeReservation(height: 60, measuredInset: 70, now: start.addingTimeInterval(3))
        precondition(dock.double(forKey: "tilesize") == 34)
        controller.synchronizeReservation(height: 60, measuredInset: 60, now: start.addingTimeInterval(6))
        precondition(restarts == 3, "Matching inset restarted the Dock")
        controller.synchronize(hidden: true)
        precondition(dock.string(forKey: "orientation") == "left")
        precondition(dock.double(forKey: "tilesize") == 72)
        precondition(dock.bool(forKey: "autohide"))
        precondition(dock.double(forKey: "autohide-delay") == 1000)
        controller.restore()
        precondition((dock.persistentDomain(forName: domain)! as NSDictionary).isEqual(to: original))
    }

    private static func testReservationAbsentKeysAndCrashRecovery() {
        let (domain, dock, task, cleanup) = testDefaults()
        defer { cleanup() }
        dock.set(["keep"], forKey: "persistent-apps")
        let original = dock.persistentDomain(forName: domain)!
        var restarts = 0
        var first: SystemDockVisibilityController? = SystemDockVisibilityController(
            domain: domain, dockDefaults: dock, snapshotDefaults: task, restartDock: { restarts += 1 })
        let start = Date()
        first!.synchronizeReservation(height: 60, now: start)
        for step in 1...8 {
            first!.synchronizeReservation(height: 60, measuredInset: 100,
                now: start.addingTimeInterval(Double(step * 3)))
        }
        precondition(restarts <= 3, "Calibration restarted indefinitely")
        first = nil // Simulate losing the controller without restoring preferences.
        let recovered = SystemDockVisibilityController(domain: domain, dockDefaults: dock,
            snapshotDefaults: task, restartDock: { restarts += 1 })
        recovered.synchronizeReservation(height: 60, accessAllowed: false)
        precondition((dock.persistentDomain(forName: domain)! as NSDictionary).isEqual(to: original),
            "Crash recovery did not restore absent keys")
        let count = restarts
        recovered.restore()
        precondition(restarts == count, "Repeated restore restarted Dock")
    }

    private static func testDefaults() -> (String, UserDefaults, UserDefaults, () -> Void) {
        let suffix = UUID().uuidString
        let dockDomain = "com.taskdock.test.dock.\(suffix)"
        let taskDomain = "com.taskdock.test.settings.\(suffix)"
        let dock = UserDefaults(suiteName: dockDomain)!
        let task = UserDefaults(suiteName: taskDomain)!
        return (dockDomain, dock, task, {
            dock.removePersistentDomain(forName: dockDomain)
            task.removePersistentDomain(forName: taskDomain)
        })
    }
}
