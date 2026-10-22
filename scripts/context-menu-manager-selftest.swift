import Foundation

@main
struct ContextMenuManagerSelftest {
    static func main() throws {
        let extensions = ContextMenuBackend.finderProviders("""
        + com.taskdock.app.finder(1.6.1) ABC /Applications/TaskDock.app/Contents/PlugIns/TaskDockFinder.appex
        - com.example.off(1) ABC /Applications/Example Off.app/Contents/PlugIns/Menu.appex
          com.example.default(2) DEF 2026-10-23 12:30:00 +0000 /Applications/Default.app/Contents/PlugIns/Menu.appex
        + com.example.on(3) GHI /Applications/On.app/Contents/PlugIns/Menu.appex
        """)
        precondition(extensions.count == 3)
        precondition(extensions[0].disabled && extensions[0].name == "Example Off")
        precondition(extensions[1].state.isEmpty && !extensions[1].disabled)
        precondition(extensions[1].path == "/Applications/Default.app/Contents/PlugIns/Menu.appex")
        precondition(extensions[2].state == "+")
        let original: [String: Any] = ["enabled_services_menu": false, "shortcut": "keep", "presentation_modes": ["ServicesMenu": false, "Other": true]]
        let hidden = ContextMenuBackend.contextStatus(original, enabled: false)
        precondition(hidden["enabled_services_menu"] as? Bool == false)
        precondition(hidden["shortcut"] as? String == "keep")
        let modes = hidden["presentation_modes"] as! [String: Any]
        precondition(modes["ServicesMenu"] as? Bool == false && modes["Other"] as? Bool == true)
        precondition(modes["ContextMenu"] as? Bool == false)
        let live = try ContextMenuBackend.scan()
        precondition(!live.contains { $0.id == "finder:com.taskdock.app.finder" })
        print("CONTEXT_MENU_MANAGER_OK: \(live.count) providers; system preferences unchanged")
        for item in live { print("\(item.kind): \(item.name) | \(item.disabled ? "disabled" : item.state.isEmpty ? "default" : "enabled")") }
    }
}
