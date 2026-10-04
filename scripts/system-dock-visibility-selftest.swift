import Foundation

@main
@MainActor
struct SystemDockVisibilitySelfTest {
    static func main() {
        testHiddenVisibleExit()
        testVisibleAtLaunchAndControllerRestart()
        testOriginallyUnsetPreferences()
        testTemporaryTaskbarHideAndReturn()
        print("DOCK_VISIBILITY_OK")
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
