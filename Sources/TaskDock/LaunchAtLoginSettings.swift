import Combine
import ServiceManagement

/// Login-item state belongs to macOS, not to the appearance/defaults snapshot.
final class LaunchAtLoginSettings: ObservableObject {
    enum State { case disabled, enabled, requiresApproval, notFound, unsupported }
    struct Backend {
        let read: () -> State
        let register: () throws -> Void
        let unregister: () throws -> Void
        let openSettings: () -> Void

        static var system: Backend {
            if #available(macOS 13.0, *) {
                return Backend(read: {
                    switch SMAppService.mainApp.status {
                    case .enabled: return .enabled
                    case .requiresApproval: return .requiresApproval
                    case .notRegistered: return .disabled
                    case .notFound: return .notFound
                    @unknown default: return .notFound
                    }
                }, register: { try SMAppService.mainApp.register() },
                   unregister: { try SMAppService.mainApp.unregister() },
                   openSettings: { SMAppService.openSystemSettingsLoginItems() })
            }
            return Backend(read: { .unsupported }, register: {}, unregister: {}, openSettings: {})
        }
    }

    @Published private(set) var state: State = .disabled
    @Published private(set) var errorMessage: String?
    private let backend: Backend
    init(backend: Backend = .system) { self.backend = backend; refresh() }

    var isOn: Bool { state == .enabled || state == .requiresApproval }
    var isSupported: Bool { state != .unsupported }
    var detail: String {
        switch state {
        case .enabled: return "登录 Mac 后自动启动 TaskDock。"
        case .disabled: return "开启后，登录 Mac 时自动启动 TaskDock。"
        case .requiresApproval: return "已申请开机启动，等待系统允许；请在系统登录项中开启。"
        case .notFound: return "请将 TaskDock 放入“应用程序”文件夹后再开启。"
        case .unsupported: return "此开关需要 macOS 13 或更高版本。"
        }
    }
    func refresh() { state = backend.read() }
    func setEnabled(_ enabled: Bool) {
        guard isSupported else { return }
        errorMessage = nil
        do {
            if enabled {
                if state == .requiresApproval { backend.openSettings() }
                else if state != .enabled { try backend.register() }
            } else if isOn { try backend.unregister() }
        } catch {
            errorMessage = "未能更改开机启动：\(error.localizedDescription)"
        }
        refresh()
    }
    func openSystemSettings() { backend.openSettings() }
}
