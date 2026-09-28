import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case taskbar
    case dockCompanion
    case matrix

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general: return "通用"
        case .taskbar: return "任务栏模式"
        case .dockCompanion: return "融合模式"
        case .matrix: return "矩阵模式"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .taskbar: return "rectangle.bottomthird.inset.filled"
        case .dockCompanion: return "dock.rectangle"
        case .matrix: return "rectangle.grid.2x2.fill"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @StateObject private var updateChecker = UpdateChecker()
    @State private var selectedTab: SettingsTab = .general
    let windows: [WindowModel]
    let onChanged: () -> Void

    private var apps: [(key: String, name: String, icon: NSImage?)] {
        let grouped = Dictionary(grouping: windows, by: { $0.appKey })
        let appKeys = Set(grouped.keys)
            .union(settings.blacklistedAppKeys)
            .union(settings.dockCompanionLeftAppKeys)
            .union(settings.dockCompanionRightAppKeys)
        return appKeys.map { key in
            if let first = grouped[key]?.first {
                return (key, first.applicationName, first.applicationIcon)
            }
            return applicationFallback(for: key)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("TaskDock 设置")
                    .font(.title2.weight(.semibold))
                Spacer()
                Text("当前模式：\(settings.layoutMode.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 10)

            TabView(selection: $selectedTab) {
                generalTab
                    .tabItem { Label(SettingsTab.general.label, systemImage: SettingsTab.general.systemImage) }
                    .tag(SettingsTab.general)

                taskbarTab
                    .tabItem { Label(SettingsTab.taskbar.label, systemImage: SettingsTab.taskbar.systemImage) }
                    .tag(SettingsTab.taskbar)

                dockCompanionTab
                    .tabItem { Label(SettingsTab.dockCompanion.label, systemImage: SettingsTab.dockCompanion.systemImage) }
                    .tag(SettingsTab.dockCompanion)

                matrixTab
                    .tabItem { Label(SettingsTab.matrix.label, systemImage: SettingsTab.matrix.systemImage) }
                    .tag(SettingsTab.matrix)
            }
        }
        .frame(minWidth: 500, minHeight: 660)
    }

    private var generalTab: some View {
        tabScrollView {
            settingsSection(title: "模式与主题", description: "选择 TaskDock 的显示模式和整体明暗主题。") {
                Picker("显示模式", selection: $settings.layoutMode) {
                    ForEach(TaskDockLayoutMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.systemImage).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: settings.layoutMode) { _ in onChanged() }

                Picker("主题", selection: $settings.appearance) {
                    ForEach(TaskbarAppearance.allCases) { appearance in
                        Label(
                            appearance.label,
                            systemImage: appearance == .light ? "sun.max.fill" : "moon.fill"
                        )
                        .tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: settings.appearance) { _ in onChanged() }
            }

            settingsSection(title: "任务项外观", description: "设置窗口卡片的高亮和文字显示。") {
                Picker("任务项高亮颜色", selection: $settings.taskItemHighlightStyle) {
                    ForEach(TaskItemHighlightStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: settings.taskItemHighlightStyle) { _ in onChanged() }

                Toggle("显示隐藏 App 的窗口", isOn: $settings.showHiddenApps)
                    .onChange(of: settings.showHiddenApps) { _ in onChanged() }

                Toggle("显示 App 名称", isOn: $settings.showApplicationName)
                    .onChange(of: settings.showApplicationName) { _ in onChanged() }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("非选中项透明度")
                        Spacer()
                        Text("\(Int(settings.nonSelectedItemTransparency * 100))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.nonSelectedItemTransparency, in: 0...0.7, step: 0.05)
                        .onChange(of: settings.nonSelectedItemTransparency) { _ in onChanged() }
                    Text("只影响非当前焦点的任务项。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            settingsSection(title: "窗口显示", description: "控制隐藏 App 的窗口是否纳入 TaskDock。") {
                Toggle("显示隐藏 App 的窗口", isOn: $settings.showHiddenApps)
                    .onChange(of: settings.showHiddenApps) { _ in onChanged() }
            }

            settingsSection(title: "系统 Dock", description: "TaskDock 运行时隐藏原生 Dock；关闭此选项或退出 TaskDock 后恢复原设置。") {
                Toggle("隐藏系统 Dock", isOn: $settings.hideSystemDock)
                    .onChange(of: settings.hideSystemDock) { _ in onChanged() }
                Text("启用后原生 Dock 不会在屏幕边缘弹出；可随时在这里关闭。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            settingsSection(title: "隐藏/显示快捷键", description: "连续按两次选定的修饰键。") {
                Picker("隐藏/显示 TaskDock 快捷键", selection: $settings.toggleModifier) {
                    ForEach(TaskbarToggleModifier.allCases) { modifier in
                        Text(modifier.label).tag(modifier)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            settingsSection(
                title: "App 黑名单",
                description: "开启后，该 App 的全部窗口都不会显示在 TaskDock 中。"
            ) {
                if apps.isEmpty {
                    emptyState("当前没有可配置的 App")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(apps.enumerated()), id: \.element.key) { index, app in
                            Toggle(isOn: Binding(
                                get: { settings.blacklistedAppKeys.contains(app.key) },
                                set: { _ in
                                    settings.toggleBlacklist(for: app.key)
                                    onChanged()
                                }
                            )) {
                                HStack(spacing: 9) {
                                    Image(nsImage: app.icon ?? fallbackIcon)
                                        .resizable()
                                        .frame(width: 22, height: 22)
                                    Text(app.name).lineLimit(1)
                                }
                            }
                            .padding(.vertical, 7)
                            if index < apps.count - 1 { Divider() }
                        }
                    }
                }
            }

            settingsSection(
                title: "窗口类型屏蔽",
                description: "从任务项右键菜单屏蔽的窗口类型会列在这里；可随时恢复显示。"
            ) {
                if settings.blockedWindowRules.isEmpty {
                    emptyState("尚未屏蔽任何窗口类型")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(settings.blockedWindowRules.enumerated()), id: \.element.id) { index, rule in
                            HStack(spacing: 10) {
                                Image(nsImage: blockedRuleIcon(for: rule))
                                    .resizable()
                                    .frame(width: 24, height: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(rule.applicationName)
                                        .font(.callout.weight(.medium))
                                        .lineLimit(1)
                                    Text(rule.windowLabel)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Button("恢复显示") {
                                    settings.removeBlockedWindowRule(rule)
                                    onChanged()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .accessibilityLabel("恢复显示 \(rule.applicationName) 的 \(rule.windowLabel)")
                            }
                            .padding(.vertical, 7)
                            if index < settings.blockedWindowRules.count - 1 { Divider() }
                        }
                    }
                }
            }

            settingsSection(title: "软件更新", description: "当前版本 \(updateChecker.currentVersion)") {
                HStack {
                    Button("检查更新") { updateChecker.check() }
                        .disabled(isChecking)
                    Spacer()
                    updateStatusView
                }
            }
        }
    }

    private var taskbarTab: some View {
        tabScrollView {
            modeHeader(
                title: "任务栏模式",
                description: "显示所有可用窗口，并支持收藏 App、拖动排序和位置对齐。",
                systemImage: SettingsTab.taskbar.systemImage,
                mode: .taskbar
            )

            settingsSection(title: "位置与长度", description: "设置任务栏在屏幕底部的对齐方式和宽度。") {
                Picker("任务栏位置", selection: $settings.taskbarAlignment) {
                    ForEach(TaskbarAlignment.allCases) { alignment in
                        Text(alignment.label).tag(alignment)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .disabled(settings.taskbarWidthMode == .fullWidth)
                .onChange(of: settings.taskbarAlignment) { _ in onChanged() }
                if settings.taskbarWidthMode == .fullWidth {
                    Text("左右铺满时，任务栏会固定从屏幕可用区域左边延伸到右边。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Picker("任务栏长度", selection: $settings.taskbarWidthMode) {
                    ForEach(TaskbarWidthMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .onChange(of: settings.taskbarWidthMode) { _ in onChanged() }
            }

            settingsSection(title: "收藏 App", description: "收藏固定在任务栏左侧；也可从任务项右键菜单添加。") {
                HStack {
                    Button {
                        chooseFavoriteApplications()
                    } label: {
                        Label("添加 App…", systemImage: "plus")
                    }
                    Spacer()
                }
                Toggle("收藏图标悬停反馈", isOn: $settings.favoriteMagnificationEnabled)
                    .onChange(of: settings.favoriteMagnificationEnabled) { _ in onChanged() }
                Text("收藏区域悬停时会轻微提亮；此开关控制单个图标下方的提示条。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Divider()
                if settings.favoriteApps.isEmpty {
                    emptyState("尚未收藏 App")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(settings.favoriteApps.enumerated()), id: \.element.id) { index, favorite in
                            HStack(spacing: 10) {
                                Image(nsImage: favoriteIcon(for: favorite))
                                    .resizable()
                                    .frame(width: 26, height: 26)
                                Text(favorite.applicationName).lineLimit(1)
                                Spacer()
                                Button("移除") {
                                    settings.removeFavorite(favorite)
                                    onChanged()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding(.vertical, 7)
                            if index < settings.favoriteApps.count - 1 { Divider() }
                        }
                    }
                }
            }
        }
    }

    private var dockCompanionTab: some View {
        tabScrollView {
            modeHeader(
                title: "融合模式",
                description: "分别选择 Dock 左右两侧显示的 App，并设置进入融合栏所需的窗口数量。",
                systemImage: SettingsTab.dockCompanion.systemImage,
                mode: .dockCompanion
            )

            settingsSection(title: "左侧 App", description: "所选 App 的窗口显示在原生 Dock 左边。") {
                dockCompanionAppList(side: .left)
            }

            settingsSection(title: "右侧 App", description: "初始为自动显示未放在左侧的 App；更改任一选项后，将按此列表决定是否显示。") {
                dockCompanionAppList(side: .right)
            }

            settingsSection(title: "窗口与栏位", description: "设置融合栏显示条件和底栏外观。Finder 不受窗口数量门槛限制。") {
                Stepper(value: Binding(
                    get: { settings.dockCompanionMinimumWindowCount },
                    set: { settings.dockCompanionMinimumWindowCount = min(max($0, 1), 20) }
                ), in: 1...20) {
                    HStack {
                        Text("至少需要的窗口数")
                        Spacer()
                        Text("\(settings.dockCompanionMinimumWindowCount) 个")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: settings.dockCompanionMinimumWindowCount) { _ in onChanged() }
                Divider()
                Toggle("显示底栏", isOn: $settings.dockCompanionShowsBottomBar)
                    .onChange(of: settings.dockCompanionShowsBottomBar) { _ in onChanged() }
                Text("关闭后隐藏底栏背景和功能按钮，只显示任务项；任务项高度会与 Dock 一致。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            settingsSection(title: "Dock 联动", description: "融合栏跟随 Dock 的基础尺寸，不跟随鼠标悬停时的临时放大。") {
                HStack {
                    Label("当前检测高度", systemImage: "arrow.up.and.down")
                    Spacer()
                    Text("\(Int(settings.dockCompanionHeight.rounded())) pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Divider()
                Label("融合栏、任务项、图标和文字会按比例同步缩放", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                Label("Finder 不受窗口数量门槛影响，仍按左右 App 选择显示", systemImage: "finder")
                Label("融合模式不显示收藏栏", systemImage: "star.slash")
            }

            settingsSection(title: "Dock 覆盖实验", description: "将 Finder 任务项叠在 Dock 左端，其他任务项叠在右端。默认关闭，可随时切回原融合布局。") {
                Toggle("叠加到 Dock 图标区（实验）", isOn: $settings.dockCompanionOverlayEnabled)
                    .onChange(of: settings.dockCompanionOverlayEnabled) { _ in onChanged() }
                Label("实验模式会覆盖 Dock 两端的图标位置；关闭即可恢复原融合布局。", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func dockCompanionAppList(side: DockCompanionAppSide) -> some View {
        if apps.isEmpty {
            emptyState("当前没有可配置的 App")
        } else {
            VStack(spacing: 0) {
                ForEach(Array(apps.enumerated()), id: \.element.key) { index, app in
                    Toggle(isOn: Binding(
                        get: {
                            switch side {
                            case .left:
                                return settings.dockCompanionLeftAppKeys.contains(app.key)
                            case .right:
                                return settings.dockCompanionSide(
                                    for: app.key,
                                    availableAppKeys: dockCompanionAvailableAppKeys
                                ) == .right
                            case .hidden:
                                return false
                            }
                        },
                        set: { isSelected in
                            switch side {
                            case .left:
                                settings.setDockCompanionLeft(isSelected, appKey: app.key)
                            case .right:
                                settings.setDockCompanionRight(
                                    isSelected,
                                    appKey: app.key,
                                    availableAppKeys: dockCompanionAvailableAppKeys
                                )
                            case .hidden:
                                break
                            }
                            onChanged()
                        }
                    )) {
                        HStack(spacing: 9) {
                            Image(nsImage: app.icon ?? fallbackIcon)
                                .resizable()
                                .frame(width: 22, height: 22)
                            Text(app.name).lineLimit(1)
                        }
                    }
                    .padding(.vertical, 7)
                    if index < apps.count - 1 { Divider() }
                }
            }
        }
    }

    private var dockCompanionAvailableAppKeys: Set<String> {
        Set(apps.map(\.key))
    }

    private var matrixTab: some View {
        tabScrollView {
            modeHeader(
                title: "矩阵模式",
                description: "按 App 分列展示窗口，适合同时查看和切换较多窗口。",
                systemImage: SettingsTab.matrix.systemImage,
                mode: .matrix
            )

            settingsSection(title: "排列方式", description: "矩阵会自动根据可用宽度压缩任务项。") {
                Label("每个 App 独立成列", systemImage: "rectangle.split.3x1")
                Label("最先打开的窗口排列在底部", systemImage: "arrow.down.to.line")
                Label("按住 Option 并拖动可移动整个矩阵", systemImage: "option")
            }
        }
    }

    private func tabScrollView<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content()
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func settingsSection<Content: View>(
        title: String,
        description: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            if let description {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }

    private func modeHeader(
        title: String,
        description: String,
        systemImage: String,
        mode: TaskDockLayoutMode
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .medium))
                .frame(width: 34, height: 34)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title3.weight(.semibold))
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if settings.layoutMode != mode {
                Button("切换到此模式") {
                    settings.layoutMode = mode
                    onChanged()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else {
                Label("正在使用", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
    }

    private func applicationFallback(for key: String) -> (key: String, name: String, icon: NSImage?) {
        if key.hasPrefix("name:") {
            return (key, String(key.dropFirst("name:".count)), nil)
        }
        let workspace = NSWorkspace.shared
        guard let applicationURL = workspace.urlForApplication(withBundleIdentifier: key) else {
            return (key, key, nil)
        }
        let bundle = Bundle(url: applicationURL)
        let displayName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        let bundleName = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
        let name = displayName ?? bundleName ?? applicationURL.deletingPathExtension().lastPathComponent
        return (key, name, workspace.icon(forFile: applicationURL.path))
    }

    private func blockedRuleIcon(for rule: BlockedWindowRule) -> NSImage {
        applicationFallback(for: rule.appKey).icon ?? fallbackIcon
    }

    private func favoriteIcon(for favorite: FavoriteApp) -> NSImage {
        let workspace = NSWorkspace.shared
        if let bundleIdentifier = favorite.bundleIdentifier,
           let applicationURL = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return workspace.icon(forFile: applicationURL.path)
        }
        if let bundlePath = favorite.bundlePath {
            return workspace.icon(forFile: bundlePath)
        }
        return fallbackIcon
    }

    private func chooseFavoriteApplications() {
        let panel = NSOpenPanel()
        panel.title = "添加收藏 App"
        panel.message = "选择要固定到任务栏左侧的 App"
        panel.prompt = "添加"
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.begin { response in
            guard response == .OK else { return }
            let addedCount = panel.urls.reduce(0) { count, url in
                count + (settings.addFavorite(applicationURL: url) ? 1 : 0)
            }
            if addedCount > 0 { onChanged() }
        }
    }

    private var fallbackIcon: NSImage {
        NSImage(named: NSImage.applicationIconName) ?? NSImage(size: NSSize(width: 24, height: 24))
    }

    private var isChecking: Bool {
        switch updateChecker.status {
        case .checking, .downloading, .verifying, .installing: return true
        default: return false
        }
    }

    @ViewBuilder
    private var updateStatusView: some View {
        switch updateChecker.status {
        case .idle:
            Text("可检查 GitHub Release")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .checking:
            updateProgress("正在检查…")
        case .upToDate(let version):
            Label("已是最新版（\(version)）", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .updateAvailable(let update):
            Button("下载并重启 \(update.version)") { updateChecker.downloadAndRestart(update) }
                .controlSize(.small)
        case .downloading(let version):
            updateProgress("正在下载 \(version)…")
        case .verifying:
            updateProgress("正在验证…")
        case .installing:
            updateProgress("正在安装并重启…")
        case .failed(let message, let releaseURL):
            HStack {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                if let releaseURL {
                    Button("打开发布页") { updateChecker.openRelease(releaseURL) }
                }
            }
            .font(.caption)
        }
    }

    private func updateProgress(_ text: String) -> some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text(text)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
