import SwiftUI

enum DeveloperDebugSettings {
    static let entryVisibleKey = "developerDebugSettingsVisibleV1"
    static let bubbleTransparencyKey = "floatingBubbleBackgroundTransparencyV1"
    static let smallBubbleFontSizeKey = "smallBubbleFontSizeV1"
    static let smallBubbleIconGapKey = "smallBubbleIconGapV1"
}

enum TaskbarItemHazeSettings {
    static let strengthKey = "taskbarItemHazeStrengthV1"
}

enum TaskbarBlackBackgroundSettings {
    static let transparencyKey = "taskbarBlackBackgroundTransparencyV1"
}

struct PointerWindowAvoidanceSettingsView: View {
    @AppStorage(PointerWindowAvoidanceSettings.animationDurationKey)
    private var animationDuration = PointerWindowAvoidanceSettings.defaultAnimationDuration
    @AppStorage(PointerWindowAvoidanceSettings.triggerDelayKey)
    private var triggerDelay = PointerWindowAvoidanceSettings.defaultTriggerDelay
    @AppStorage(PointerWindowAvoidanceSettings.tiledDelayKey) private var tiledDelay = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("抬脚动画时长")
                ReleaseTunedSlider(value: $animationDuration, in: 0.08...0.6, defaultValue: ReleaseTunedSlider.preset(PointerWindowAvoidanceSettings.animationDurationKey, fallback: 0.24))
                    .accessibilityLabel("窗口抬脚动画时长")
                Text(String(format: "%.2f 秒", animationDuration))
                    .monospacedDigit().frame(width: 72, alignment: .trailing)
            }
            Text("数值越小，窗口抬起越快；滑杆标记处为发布默认值。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("触发延时")
                ReleaseTunedSlider(value: $triggerDelay, in: 0...1.5, defaultValue: ReleaseTunedSlider.preset(PointerWindowAvoidanceSettings.triggerDelayKey, fallback: 0))
                    .accessibilityLabel("窗口抬脚触发延时")
                Text(String(format: "%.2f 秒", triggerDelay))
                    .monospacedDigit().frame(width: 72, alignment: .trailing)
            }
            Text("鼠标进入屏幕底部区域后等待的时间；0 秒立即检查。最大化窗口的自动避让不受此项影响。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("最大化／半屏延时")
                ReleaseTunedSlider(value: $tiledDelay, in: 0...2,
                    defaultValue: ReleaseTunedSlider.preset(PointerWindowAvoidanceSettings.tiledDelayKey, fallback: 0))
                    .accessibilityLabel("最大化和半屏窗口避让延时")
                Text(String(format: "%.2f 秒", tiledDelay)).monospacedDigit().frame(width: 72, alignment: .trailing)
            }
        }
    }
}

struct TaskbarBlackBackgroundSettingsView: View {
    @AppStorage(TaskbarBlackBackgroundSettings.transparencyKey) private var transparency = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("黑色底色透明度")
                ReleaseTunedSlider(value: $transparency, in: 0...1, defaultValue: ReleaseTunedSlider.preset(TaskbarBlackBackgroundSettings.transparencyKey, fallback: 1))
                    .accessibilityLabel("任务栏黑色底色透明度")
                Text("\(Int((transparency * 100).rounded()))%")
                    .monospacedDigit().frame(width: 44, alignment: .trailing)
            }
            Text("在整条任务栏玻璃上叠加黑色。0% 为纯黑，100% 不显示黑色；只影响底色，自动保存并即时生效。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct TaskbarItemHazeSettingsView: View {
    @AppStorage(TaskbarItemHazeSettings.strengthKey) private var strength = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("胶囊底色强度")
                ReleaseTunedSlider(value: $strength, in: 0...1, defaultValue: ReleaseTunedSlider.preset(TaskbarItemHazeSettings.strengthKey, fallback: 1))
                    .accessibilityLabel("任务项胶囊底色强度")
                Text("\(Int((strength * 100).rounded()))%")
                    .monospacedDigit().frame(width: 44, alignment: .trailing)
            }
            Text("调整任务栏中激活项和鼠标悬停项的平面底色。0% 为无底色，100% 为完整效果；自动保存并即时生效。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct DeveloperDebugSettingsView: View {
    @AppStorage(DeveloperDebugSettings.bubbleTransparencyKey) private var transparency = 0.0
    @AppStorage(DeveloperDebugSettings.smallBubbleFontSizeKey) private var smallBubbleFontSize = 12.0
    @AppStorage(DeveloperDebugSettings.smallBubbleIconGapKey) private var smallBubbleIconGap = 3.0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("大气泡用于菜单和列表；小气泡用于收藏栏 App 名称和移除收藏提醒。")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Text("背景透明度")
                ReleaseTunedSlider(value: $transparency, in: 0...0.9, defaultValue: ReleaseTunedSlider.preset(DeveloperDebugSettings.bubbleTransparencyKey, fallback: 0))
                    .accessibilityLabel("浮动气泡窗口背景透明度")
                Text("\(Int((transparency * 100).rounded()))%")
                    .monospacedDigit().frame(width: 44, alignment: .trailing)
            }
            Text("背景使用毛玻璃效果。0% 为最实，90% 为最透明；文字和按钮不参与模糊，设置自动保存。")
                .font(.caption).foregroundStyle(.secondary)
            Text("实时预览").font(.subheadline.bold())
            ZStack {
                LinearGradient(colors: [.blue.opacity(0.4), .orange.opacity(0.3)], startPoint: .leading, endPoint: .trailing)
                FloatingBubbleSurface(arrowX: 30) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("浮动气泡窗口").font(.headline)
                        Label("背景变化，内容保持清楚", systemImage: "checkmark.circle.fill")
                    }.padding(16).frame(width: 300, alignment: .leading)
                }.padding(24)
            }.frame(height: 160).clipShape(RoundedRectangle(cornerRadius: 12))
            Button("恢复默认透明度") {
                transparency = ReleaseTunedSlider.preset(DeveloperDebugSettings.bubbleTransparencyKey, fallback: 0)
            }
            Divider()
            Text("小气泡").font(.headline)
            HStack {
                Text("字号").frame(width: 110, alignment: .leading)
                ReleaseTunedSlider(value: $smallBubbleFontSize, in: 9...20, defaultValue: ReleaseTunedSlider.preset(DeveloperDebugSettings.smallBubbleFontSizeKey, fallback: 12))
                    .accessibilityLabel("小气泡字号")
                numberInput("小气泡字号数值", value: $smallBubbleFontSize, range: 9...20)
            }
            HStack {
                Text("距图标的距离").frame(width: 110, alignment: .leading)
                ReleaseTunedSlider(value: $smallBubbleIconGap, in: 0...30, defaultValue: ReleaseTunedSlider.preset(DeveloperDebugSettings.smallBubbleIconGapKey, fallback: 3))
                    .accessibilityLabel("小气泡距图标的距离")
                numberInput("小气泡距离数值", value: $smallBubbleIconGap, range: 0...30)
            }
            Text("距离从尖尖底部量到图标顶部。两项设置同时用于名称和移除提醒，即时生效并自动保存。")
                .font(.caption).foregroundStyle(.secondary)
            VStack(spacing: smallBubbleIconGap) {
                FloatingBubbleSurface(arrowX: 60, isSmall: true) {
                    Text("App 名称")
                        .font(.system(size: smallBubbleFontSize, weight: .regular))
                        .frame(width: 120, height: smallBubbleFontSize + SmallBubbleMetrics.textVerticalPadding)
                }
                Image(systemName: "app.fill").font(.system(size: 36)).foregroundStyle(.blue)
            }.frame(maxWidth: .infinity).frame(height: 130)
            Button("恢复小气泡默认值") {
                smallBubbleFontSize = ReleaseTunedSlider.preset(DeveloperDebugSettings.smallBubbleFontSizeKey, fallback: 12)
                smallBubbleIconGap = ReleaseTunedSlider.preset(DeveloperDebugSettings.smallBubbleIconGapKey, fallback: 3)
            }
        }
    }

    private func numberInput(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack(spacing: 4) {
            TextField(label, value: Binding(
                get: { value.wrappedValue },
                set: { if $0.isFinite { value.wrappedValue = min(range.upperBound, max(range.lowerBound, $0.rounded())) } }
            ), formatter: Self.integerFormatter)
                .textFieldStyle(.roundedBorder).frame(width: 48)
                .accessibilityLabel(label)
            Text("pt").foregroundStyle(.secondary)
        }
    }

    private static let integerFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.allowsFloats = false
        formatter.usesGroupingSeparator = false
        return formatter
    }()
}

struct ExperimentalTaskbarGlassSettingsView: View {
    // Reuse the experiment preference so existing local previews keep their appearance.
    @AppStorage(TaskbarExperimentalGlass.preferenceKey) private var customEnabled = false
    @AppStorage(TaskbarExperimentalGlass.clarityKey) private var clarity = 1.0
    private var followsSystem: Binding<Bool> {
        Binding(get: { !customEnabled }, set: { customEnabled = !$0 })
    }
    private var sliderValue: Binding<Double> {
        Binding(get: { TaskbarExperimentalGlass.normalizedClarity(clarity) },
                set: { clarity = TaskbarExperimentalGlass.normalizedClarity($0) })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("液态玻璃效果跟随系统", isOn: followsSystem)
                .disabled(!TaskbarExperimentalGlass.isSupported)
            Text("开启后跟随系统的液态玻璃设置；关闭后使用下方数值，系统玻璃滑杆不再影响 TaskDock。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("通透度")
                Text("磨砂").font(.caption).foregroundStyle(.secondary)
                ReleaseTunedSlider(value: sliderValue, in: 0...1, defaultValue: ReleaseTunedSlider.preset(TaskbarExperimentalGlass.clarityKey, fallback: 1))
                    .accessibilityLabel("任务栏玻璃通透度")
                Text("通透").font(.caption).foregroundStyle(.secondary)
                Text("\(Int((sliderValue.wrappedValue * 100).rounded()))%")
                    .monospacedDigit().frame(width: 44, alignment: .trailing)
            }
            .disabled(!customEnabled || !TaskbarExperimentalGlass.isSupported)
            Text(TaskbarExperimentalGlass.isSupported
                 ? "仅影响任务栏玻璃，文字和图标保持清晰。手动数值自动保存，跟随系统时暂不生效。手动模式使用实验接口，系统更新后可能需要恢复跟随系统。"
                 : "此系统版本尚未验证手动模式，当前使用系统玻璃效果。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
