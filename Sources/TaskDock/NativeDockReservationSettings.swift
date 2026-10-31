import SwiftUI

enum NativeDockReservationSettings {
    static let enabledKey = "taskdock.nativeDockReservationExperimentV1"
    static let statusKey = "taskdock.nativeDockReservationStatusV1"
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
}

struct NativeDockReservationSettingsView: View {
    @AppStorage(NativeDockReservationSettings.enabledKey) private var enabled = false
    @AppStorage(NativeDockReservationSettings.statusKey) private var status = "尚未启用"
    let onChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("原生 Dock 占位（实验）", isOn: $enabled)
                .onChange(of: enabled) { _ in onChanged() }
            Text("让原生 Dock 在 TaskDock 下方预留空间，实验期间停用抬脚。切换会重启 Dock；关闭实验、退出或切回原生 Dock 时恢复原设置。")
                .font(.caption).foregroundStyle(.secondary)
            Text("透明背景可能透出原生图标或名称提示；不适用于独立全屏空间。")
                .font(.caption).foregroundStyle(.secondary)
            if enabled { Text(status).font(.caption).foregroundStyle(.secondary) }
        }
    }
}
