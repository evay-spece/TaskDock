import AppKit
import TaskDockBrowserProtocol

/// Registration is opt-in, invoked only by the settings buttons.
enum BrowserProgressIntegration {
    static var hostURL: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/TaskDockBrowserHost")
    }
    static var extensionURL: URL? { Bundle.main.resourceURL?.appendingPathComponent("BrowserExtension", isDirectory: true) }
    static func configured(_ browser: ProgressBrowser) -> Bool {
        let url = BrowserBridgeRegistration.manifestURL(browser: browser)
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return object["path"] as? String == hostURL.path && object["allowed_origins"] as? [String] == [BrowserBridgeIdentity.origin]
    }
    static func register(_ browser: ProgressBrowser) throws {
        try BrowserBridgeRegistration.register(browser: browser, executable: hostURL)
    }
    static func unregister(_ browser: ProgressBrowser) throws {
        try BrowserBridgeRegistration.unregister(browser: browser, executable: hostURL)
    }
    static func openExtensionFolder() {
        guard let extensionURL else { return }
        NSWorkspace.shared.open(extensionURL)
    }
    static func openInstructions() {
        guard let extensionURL else { return }
        NSWorkspace.shared.open(extensionURL.appendingPathComponent("安装说明.txt"))
    }
}
