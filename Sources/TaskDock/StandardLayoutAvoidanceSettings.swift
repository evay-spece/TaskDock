import SwiftUI

/// Runtime-only contrast override; never persisted to user appearance defaults.
final class TaskbarOverlapAppearance: ObservableObject {
    static let shared = TaskbarOverlapAppearance()
    @Published private(set) var usesTemporaryItemBackground = false
    func update(_ value: Bool) {
        guard value != usesTemporaryItemBackground else { return }
        usesTemporaryItemBackground = value
    }
}

enum StandardLayoutAvoidanceSettings {
    static let enabledKey = "taskdock.standardLayoutAvoidanceV1"
    static let overflowLimitKey = "taskdock.windowAvoidanceBottomOverflowLimitV1"
    static var bottomOverflowLimit: Double {
        let value = UserDefaults.standard.object(forKey: overflowLimitKey) as? Double ?? 48
        return value.isFinite ? min(500, max(0, value)) : 48
    }
    static let allOverlapsKey = "taskdock.allOverlappingWindowsAvoidanceV1"
    static var avoidsAllOverlaps: Bool { UserDefaults.standard.bool(forKey: allOverlapsKey) }
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
    @AppStorage(StandardLayoutAvoidanceSettings.overflowLimitKey) private var overflowLimit = 48.0
    @AppStorage(StandardLayoutAvoidanceSettings.allOverlapsKey) private var allOverlaps = false
    @AppStorage(StandardLayoutAvoidanceSettings.animatedKey) private var animated = false
    @AppStorage(PointerWindowAvoidanceSettings.animationDurationKey) private var duration = PointerWindowAvoidanceSettings.defaultAnimationDuration
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("窗口避让", isOn: $enabled)
            Text("默认仅调整当前焦点的最大化／半屏窗口。开启下方选项后，所有重叠窗口均避让，不要求焦点；拖动时暂停，应用拒绝调整时不反复重试。")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("所有重叠窗口避让", isOn: $allOverlaps)
                .disabled(!enabled)
            Text("小窗口向上移动，大窗口收底边。底边出屏超过下方阈值时跳过。沿用下方动画和等待时间。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("底边出屏阈值")
                ReleaseTunedSlider(value: $overflowLimit, in: 0...500, defaultValue: 48)
                    .accessibilityLabel("窗口底边出屏阈值")
                Text("\(Int(overflowLimit.rounded())) pt").monospacedDigit().frame(width: 60, alignment: .trailing)
            }.disabled(!enabled || !allOverlaps)
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
