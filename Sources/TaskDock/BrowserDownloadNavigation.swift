import AppKit
import TaskDockBrowserProtocol

enum BrowserDownloadNavigation {
    static func openFile(_ task: BrowserDownloadTask, reveal: Bool, completion: @escaping (Bool) -> Void) {
        guard let url = task.download.fileURL, FileManager.default.fileExists(atPath: url.path) else {
            showError("文件已移动或删除，请在浏览器下载列表中查看。")
            completion(false)
            return
        }
        let target = reveal ? url.deletingLastPathComponent() : url
        NSWorkspace.shared.open(target, configuration: NSWorkspace.OpenConfiguration()) { app, error in
            DispatchQueue.main.async {
                guard error == nil, app != nil else {
                    showError(reveal ? "无法打开所在文件夹。" : "无法打开此文件，请在 Finder 中选择其他应用。")
                    completion(false)
                    return
                }
                if reveal { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                completion(true)
            }
        }
    }
    private static func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "无法打开下载文件"
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
    static func open(_ browser: ProgressBrowser) {
        if browser == .safari {
            if let running = NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleIdentifier).first {
                running.activate(options: [.activateIgnoringOtherApps])
            } else if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleIdentifier) {
                NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
            }
            return
        }
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleIdentifier),
              let url = URL(string: browser == .chrome ? "chrome://downloads/" : "edge://downloads/") else { return }
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }
}
