import SwiftUI

enum StandardLayoutAvoidanceSettings {
    static let enabledKey = "taskdock.standardLayoutAvoidanceV1"
    static let delayKey = "taskdock.standardLayoutSettleDelayV1"
    static var isEnabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
    static var settleDelay: TimeInterval {
        let value = UserDefaults.standard.object(forKey: delayKey) as? Double ?? 0.35
        return value.isFinite ? min(max(value, 0.2), 1.5) : 0.35
    }
}

struct StandardLayoutAvoidanceSettingsView: View {
    @AppStorage(StandardLayoutAvoidanceSettings.enabledKey) private var enabled = true
    @AppStorage(StandardLayoutAvoidanceSettings.delayKey) private var delay = 0.35
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("最大化／半屏窗口避让", isOn: $enabled)
            Text("窗口布局稳定后只收一次底边，不播放抬脚动画。普通窗口、拖动中的窗口及明显出屏窗口保持原位；应用拒绝调整时不反复重试。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("布局稳定等待")
                ReleaseTunedSlider(value: $delay, in: 0.2...1.5, defaultValue: 0.35)
                    .accessibilityLabel("标准布局稳定等待")
                    .disabled(!enabled)
                Text(String(format: "%.2f 秒", delay)).monospacedDigit()
            }
        }
    }
}
