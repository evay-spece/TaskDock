import SwiftUI

enum StandardLayoutAvoidanceSettings {
    static let enabledKey = "taskdock.standardLayoutAvoidanceV1"
    static let animatedKey = "taskdock.standardLayoutAnimatedV1"
    static var isAnimated: Bool { UserDefaults.standard.bool(forKey: animatedKey) }
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
    @AppStorage(StandardLayoutAvoidanceSettings.animatedKey) private var animated = false
    @AppStorage(PointerWindowAvoidanceSettings.animationDurationKey) private var duration = PointerWindowAvoidanceSettings.defaultAnimationDuration
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("最大化／半屏窗口避让", isOn: $enabled)
            Text("窗口布局稳定后只收一次底边，可选择直接收边或动画过渡。普通窗口、拖动中的窗口及明显出屏窗口保持原位；应用拒绝调整时不反复重试。")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("收边动画过渡", isOn: $animated)
                .disabled(!enabled)
            if animated {
                HStack {
                    Text("动画时长")
                    ReleaseTunedSlider(value: $duration, in: 0.08...0.6, defaultValue: PointerWindowAvoidanceSettings.defaultAnimationDuration)
                        .accessibilityLabel("窗口收边动画时长")
                    Text(String(format: "%.2f 秒", duration)).monospacedDigit()
                }.disabled(!enabled)
            }
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
