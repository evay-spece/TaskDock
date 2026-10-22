import AppKit
import FinderSync
import Darwin
import OSLog

private let finderLog = Logger(subsystem: "com.taskdock.app", category: "FinderExtension")

@objc(TaskDockFinderExtension)
final class TaskDockFinderExtension: FIFinderSync {
    private var menuFolder: URL?
    override init() {
        super.init()
        let homePath = String(cString: getpwuid(getuid())!.pointee.pw_dir)
        let home = URL(fileURLWithPath: homePath, isDirectory: true)
        FIFinderSyncController.default().directoryURLs = [home, URL(fileURLWithPath: "/Volumes", isDirectory: true)]
        finderLog.notice("Monitoring user home and external volumes")
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard FileTypeSettings.isEnabled else { return nil }
        finderLog.notice("Menu requested")
        let controller = FIFinderSyncController.default()
        let target = controller.targetedURL() ?? controller.selectedItemURLs()?.first
        guard let target else { return nil }
        let isDirectory = (try? target.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let folder = isDirectory ? target : target.deletingLastPathComponent()
        guard folder.isFileURL else { return nil }
        menuFolder = folder

        let menu = NSMenu(title: "")
        let parent = NSMenuItem(title: "新建文件", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "新建文件")
        for (index, entry) in FileTypeSettings.load().filter(\.enabled).enumerated() {
            let item = NSMenuItem(title: entry.title, action: #selector(createFile(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            submenu.addItem(item)
        }
        if FileTypeSettings.isEntryVisible {
            if !submenu.items.isEmpty { submenu.addItem(.separator()) }
            let settings = NSMenuItem(title: "设置新建类型…", action: #selector(openSettings(_:)), keyEquivalent: "")
            settings.target = self
            submenu.addItem(settings)
        }
        parent.submenu = submenu
        if !submenu.items.isEmpty { menu.addItem(parent) }
        if menuKind == .contextualMenuForItems {
            let cut = NSMenuItem(title: "剪切  ⌘X", action: #selector(cutSelected(_:)), keyEquivalent: "x")
            cut.keyEquivalentModifierMask = [.command]
            cut.target = self
            menu.addItem(cut)
        }
        if !ClipboardCutter.cutFiles().isEmpty {
            let paste = NSMenuItem(title: "粘贴并移动  ⌘V", action: #selector(pasteAndMove(_:)), keyEquivalent: "v")
            paste.keyEquivalentModifierMask = [.command]
            paste.target = self
            paste.representedObject = folder.path
            menu.addItem(paste)
        }
        return menu
    }

    @objc private func pasteAndMove(_ sender: NSMenuItem) {
        guard FileTypeSettings.isEnabled else { return }
        guard let folderPath = (sender.representedObject as? String) ?? menuFolder?.path ?? FIFinderSyncController.default().targetedURL()?.path else { return }
        var components = URLComponents()
        components.scheme = "taskdockfile"
        components.host = "move"
        components.queryItems = [URLQueryItem(name: "folder", value: folderPath)]
        if let url = components.url { _ = NSWorkspace.shared.open(url) }
    }

    @objc private func createFile(_ sender: NSMenuItem) {
        guard FileTypeSettings.isEnabled else { return }
        let enabled = FileTypeSettings.load().filter(\.enabled)
        guard enabled.indices.contains(sender.tag) else { return }
        let kind = enabled[sender.tag].id
        let controller = FIFinderSyncController.default()
        guard let target = controller.targetedURL() ?? controller.selectedItemURLs()?.first else {
            finderLog.error("No target URL in menu action")
            return
        }
        let isDirectory = (try? target.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let folder = isDirectory ? target : target.deletingLastPathComponent()
        var components = URLComponents()
        components.scheme = "taskdockfile"
        components.host = "create"
        components.queryItems = [URLQueryItem(name: "kind", value: kind), URLQueryItem(name: "folder", value: folder.path)]
        guard let url = components.url else { return }
        let opened = NSWorkspace.shared.open(url)
        finderLog.notice("Action \(kind, privacy: .public), LaunchServices opened: \(opened, privacy: .public)")
    }

    @objc private func openSettings(_ sender: NSMenuItem) {
        guard FileTypeSettings.isEnabled, FileTypeSettings.isEntryVisible else { return }
        guard let url = URL(string: "taskdockfile://settings") else { return }
        _ = NSWorkspace.shared.open(url)
    }

    @objc private func cutSelected(_ sender: NSMenuItem) {
        guard FileTypeSettings.isEnabled else { return }
        let controller = FIFinderSyncController.default()
        let files = controller.selectedItemURLs() ?? controller.targetedURL().map { [$0] } ?? []
        let copied = ClipboardCutter.cut(files)
        finderLog.notice("Cut \(files.count) items to pasteboard: \(copied, privacy: .public)")
    }
}
