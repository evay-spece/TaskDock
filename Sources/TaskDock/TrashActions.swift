import AppKit
import ApplicationServices

enum TrashActions {
    static func latestItem() -> URL? {
        let manager = FileManager.default
        let homeTrash = manager.homeDirectoryForCurrentUser
            .appendingPathComponent(".Trash", isDirectory: true)
        let volumes = manager.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeIsLocalKey],
            options: [.skipHiddenVolumes]
        ) ?? []
        let otherTrashes = volumes.compactMap { volume -> URL? in
            guard (try? volume.resourceValues(forKeys: [.volumeIsLocalKey]).volumeIsLocal) == true
            else { return nil }
            return volume.appendingPathComponent(".Trashes", isDirectory: true)
                .appendingPathComponent(String(getuid()), isDirectory: true)
        }
        return ([homeTrash] + otherTrashes).flatMap { trash in
            (try? manager.contentsOfDirectory(
                at: trash,
                includingPropertiesForKeys: [.addedToDirectoryDateKey],
                options: []
            )) ?? []
        }
        .filter { $0.lastPathComponent != ".DS_Store" }
        .compactMap { item -> (url: URL, date: Date)? in
            guard let date = try? item.resourceValues(forKeys: [.addedToDirectoryDateKey])
                .addedToDirectoryDate else { return nil }
            return (item, date)
        }
        .max { $0.date < $1.date }?.url
    }

    static func empty(completion: @escaping (Error?) -> Void) {
        runAppleScript([
            "tell application \"Finder\" to empty trash"
        ], completion: completion)
    }

    static func restoreLatest(completion: @escaping (Error?) -> Void) {
        guard let item = latestItem() else {
            completion(NSError(domain: "TaskDock.Trash", code: 1,
                userInfo: [NSLocalizedDescriptionKey:
                    "无法确定最近删除的项目。请在“系统设置 > 隐私与安全性 > 完全磁盘访问”中允许 TaskDock，然后重试。"]))
            return
        }
        // Finder owns the original-location record. Select the precise item,
        // then invoke Finder's Put Back command; never guess its old path.
        runAppleScript([
            "on run argv",
            "set targetPath to item 1 of argv",
            "tell application \"Finder\"",
            "activate",
            "open trash",
            "set selection to (POSIX file targetPath as alias)",
            "end tell",
            "end run"
        ], arguments: [item.path]) { error in
            guard error == nil else { completion(error); return }
            if let error = pressFinderPutBack() { completion(error); return }
            DispatchQueue.global(qos: .userInitiated).async {
                for _ in 0..<20 {
                    if !FileManager.default.fileExists(atPath: item.path) {
                        DispatchQueue.main.async { completion(nil) }
                        return
                    }
                    Thread.sleep(forTimeInterval: 0.1)
                }
                DispatchQueue.main.async {
                    completion(NSError(domain: "TaskDock.Trash", code: 2,
                        userInfo: [NSLocalizedDescriptionKey:
                            "Finder 未能将该项目放回原处，请在废纸篓中手动选择“放回原处”。"]))
                }
            }
        }
    }

    private static func pressFinderPutBack() -> Error? {
        guard let finder = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.finder"
        }) else { return actionError("Finder 未运行") }
        let application = AXUIElementCreateApplication(finder.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 1)
        var menuBarValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application,
                                            kAXMenuBarAttribute as CFString,
                                            &menuBarValue) == .success,
              let menuBarValue, CFGetTypeID(menuBarValue) == AXUIElementGetTypeID()
        else { return actionError("无法读取 Finder 菜单，请在系统设置中允许 TaskDock 的辅助功能权限") }
        let menuBar = menuBarValue as! AXUIElement
        for menuBarItem in axChildren(of: menuBar) {
            guard ["文件", "File"].contains(axName(of: menuBarItem)) else { continue }
            for menu in axChildren(of: menuBarItem) {
                guard let putBack = axChildren(of: menu).first(where: {
                    ["放回原处", "Put Back"].contains(axName(of: $0))
                }) else { continue }
                let result = AXUIElementPerformAction(putBack, kAXPressAction as CFString)
                return result == .success ? nil : actionError("Finder 无法将此项目放回原处（\(result.rawValue)）")
            }
        }
        return actionError("Finder 的“放回原处”菜单不可用")
    }

    private static func axChildren(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString,
                                            &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private static func axName(of element: AXUIElement) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString,
                                            &value) == .success else { return "" }
        return value as? String ?? ""
    }

    private static func actionError(_ message: String) -> Error {
        NSError(domain: "TaskDock.Trash", code: 3,
                userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func runAppleScript(
        _ lines: [String],
        arguments: [String] = [],
        completion: @escaping (Error?) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = lines.flatMap { ["-e", $0] } + arguments
            let errors = Pipe()
            process.standardError = errors
            do {
                try process.run()
                process.waitUntilExit()
                let output = String(data: errors.fileHandleForReading.readDataToEndOfFile(),
                                    encoding: .utf8) ?? ""
                let error: Error? = process.terminationStatus == 0 ? nil : NSError(
                    domain: "TaskDock.Trash", code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey:
                        output.trimmingCharacters(in: .whitespacesAndNewlines)]
                )
                DispatchQueue.main.async { completion(error) }
            } catch {
                DispatchQueue.main.async { completion(error) }
            }
        }
    }
}
