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
    let onVisualChanged: () -> Void
    let onLayoutChanged: () -> Void

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

    private static let defaultDockCompanionApps: [(key: String, name: String)] = [
        ("com.apple.finder", "Finder"),
        ("com.apple.Safari", "Safari"),
        ("com.kingsoft.wpsoffice.mac", "WPS Office"),
        ("com.microsoft.edgemac", "Microsoft Edge"),
        ("com.google.Chrome", "Google Chrome"),
        ("com.microsoft.Excel", "Microsoft Excel")
    ]

    private var dockCompanionApps: [(key: String, name: String, icon: NSImage?)] {
        let existing = Dictionary(uniqueKeysWithValues: apps.map { ($0.key, $0) })
        let added = Dictionary(uniqueKeysWithValues: settings.dockCompanionAddedApps.map { ($0.id, $0) })
        let defaultNames = Dictionary(uniqueKeysWithValues: Self.defaultDockCompanionApps.map { ($0.key, $0.name) })
        let keys = Set(existing.keys).union(added.keys).union(defaultNames.keys)
        return keys.map { key in
            if let app = existing[key], app.name != key { return app }
            if let app = added[key] {
                return (key, app.applicationName, favoriteIcon(for: app))
            }
            let fallback = applicationFallback(for: key)
            return (key, fallback.name == key ? (defaultNames[key] ?? key) : fallback.name, fallback.icon)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ForEach(SettingsTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: tab.systemImage)
                                .font(.system(size: 25, weight: .regular))
                                .frame(height: 29)
                            HStack(spacing: 3) {
                                Text(tab.label)
                                    .font(.system(size: 12, weight: .medium))
                                if tab == .dockCompanion || tab == .matrix {
                                    Text("实验")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(.orange)
                                }
                            }
                            .lineLimit(1)
                        }
                        .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.secondary)
                        .frame(width: 106, height: 70)
                        .background {
                            if selectedTab == tab {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.primary.opacity(0.07))
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
            .padding(.bottom, 12)

            Divider()

            Group {
                switch selectedTab {
                case .general: generalTab
                case .taskbar: taskbarTab
                case .dockCompanion: dockCompanionTab
                case .matrix: matrixTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 720, minHeight: 660)
    }

    private var generalTab: some View {
        tabScrollView {
            settingsSection(title: "显示模式", description: "选择 TaskDock 当前使用的模式；外观与窗口显示在各模式中分别设置。") {
                Picker("显示模式", selection: $settings.layoutMode) {
                    ForEach(TaskDockLayoutMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.systemImage).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize(horizontal: true, vertical: false)
                .onChange(of: settings.layoutMode) { _ in onChanged() }
            }

            settingsSection(title: "任务项外观", description: "设置窗口卡片的高亮和文字显示。") {
                Picker("任务项高亮颜色", selection: $settings.taskItemHighlightStyle) {
                    ForEach(TaskItemHighlightStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize(horizontal: true, vertical: false)
                .onChange(of: settings.taskItemHighlightStyle) { _ in onVisualChanged() }

                Toggle("显示 App 名称", isOn: $settings.showApplicationName)
                    .onChange(of: settings.showApplicationName) { _ in onVisualChanged() }
            }

            settingsSection(title: "隐藏/显示快捷键", description: "连续按两次选定的修饰键。") {
                Picker("隐藏/显示 TaskDock 快捷键", selection: $settings.toggleModifier) {
                    ForEach(TaskbarToggleModifier.allCases) { modifier in
                        Text(modifier.label).tag(modifier)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize(horizontal: true, vertical: false)
                .onChange(of: settings.toggleModifier) { _ in onChanged() }
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

            modeVisualSettings(for: .taskbar)

            settingsSection(title: "位置与尺寸", description: "设置任务栏在屏幕底部的对齐方式、宽度和高度。") {
                Picker("任务栏位置", selection: $settings.taskbarAlignment) {
                    ForEach(TaskbarAlignment.allCases) { alignment in
                        Text(alignment.label).tag(alignment)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize(horizontal: true, vertical: false)
                .disabled(settings.taskbarWidthMode == .fullWidth)
                .onChange(of: settings.taskbarAlignment) { _ in onLayoutChanged() }
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
                .pickerStyle(.menu)
                .fixedSize(horizontal: true, vertical: false)
                .onChange(of: settings.taskbarWidthMode) { _ in onLayoutChanged() }
                HStack {
                    Label("任务栏高度", systemImage: "arrow.up.and.down")
                    Spacer()
                    Text("\(Int(settings.taskbarHeight.rounded())) pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: $settings.taskbarHeight, in: SettingsStore.taskbarHeightRange, step: 2)
                    .accessibilityLabel("任务栏高度")
                    .onChange(of: settings.taskbarHeight) { _ in onLayoutChanged() }
                Text("任务栏、图标和任务项同步调整；默认 38 pt。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Label("任务项文字大小", systemImage: "textformat.size")
                    Spacer()
                    Text("\(Int(settings.taskbarItemFontSize.rounded())) pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Picker("任务项文字大小", selection: $settings.taskbarItemFontSize) {
                    ForEach(SettingsStore.taskbarItemFontSizes, id: \.self) { size in
                        Text("\(Int(size))").tag(size)
                    }
                }
                    .pickerStyle(.menu)
                    .fixedSize(horizontal: true, vertical: false)
                    .onChange(of: settings.taskbarItemFontSize) { _ in onVisualChanged() }
                Text("仅调整任务栏任务项文字，共 5 档；默认 12 pt。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            settingsSection(title: "快捷键", description: "任务栏显示期间可直接使用；按下 Option 显示对应提示。") {
                Text("⌥ + J/K/L/;/'/N/M/,/.：从左到右的前 9 个窗口任务项。")
                    .font(.caption)
                Text("⌥ + 1–9：从左到右的前 9 个收藏 App。再次按相同快捷键可最小化当前窗口。")
                    .font(.caption)
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
                    .onChange(of: settings.favoriteMagnificationEnabled) { _ in onVisualChanged() }
                Text("鼠标移到收藏图标上时，图标会弹性放大；关闭后保持固定大小。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("运行中的 App 图标下方显示灰白色指示灯，无论是否有窗口。")
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

            settingsSection(title: "收藏文件夹", description: "显示在任务栏最右侧；点击图标会在 Finder 中打开。") {
                HStack {
                    Button {
                        chooseFavoriteFolders()
                    } label: {
                        Label("添加文件夹…", systemImage: "plus")
                    }
                    Spacer()
                }
                if settings.favoriteFolders.isEmpty {
                    emptyState("尚未收藏文件夹")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(settings.favoriteFolders.enumerated()), id: \.element.id) { index, folder in
                            HStack(spacing: 10) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: folder.path))
                                    .resizable()
                                    .frame(width: 26, height: 26)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(folder.name).lineLimit(1)
                                    Text(folder.path)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Button("移除") {
                                    settings.removeFavoriteFolder(folder)
                                    onChanged()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding(.vertical, 7)
                            if index < settings.favoriteFolders.count - 1 { Divider() }
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

            modeVisualSettings(for: .dockCompanion)

            settingsSection(title: "左侧 App", description: "所选 App 的窗口显示在原生 Dock 左边。") {
                dockCompanionAppList(side: .left)
            }

            settingsSection(title: "右侧 App", description: "初始为自动显示未放在左侧的 App；更改任一选项后，将按此列表决定是否显示。") {
                dockCompanionAppList(side: .right)
            }

            settingsSection(title: "快捷键", description: "按住 Option 时，融合栏任务项会显示对应按键。") {
                Text("左侧窗口：⌥ + 1–8；右侧窗口：⌥ + J/K/L/;/'。")
                    .font(.caption)
                Text("按一次切换或恢复窗口；焦点已在该窗口时，再按一次将其最小化。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            settingsSection(title: "窗口与栏位", description: "设置融合栏显示条件和底栏外观。Finder 不受窗口数量门槛限制。") {
                Picker("至少需要的窗口数", selection: Binding(
                    get: { settings.dockCompanionMinimumWindowCount },
                    set: { settings.dockCompanionMinimumWindowCount = min(max($0, 1), 20) }
                )) {
                    ForEach(1...20, id: \.self) { count in
                        Text("\(count) 个").tag(count)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize(horizontal: true, vertical: false)
                .onChange(of: settings.dockCompanionMinimumWindowCount) { _ in onChanged() }
                Divider()
                Picker("App 窗口折叠门槛", selection: Binding(
                    get: { settings.dockCompanionCollapseThreshold },
                    set: { settings.dockCompanionCollapseThreshold = min(max($0, 2), 20) }
                )) {
                    ForEach(2...20, id: \.self) { count in
                        Text("\(count) 个").tag(count)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize(horizontal: true, vertical: false)
                .onChange(of: settings.dockCompanionCollapseThreshold) { _ in onChanged() }
                Text("达到门槛后只占一个位置；点击 App 入口可选择具体窗口。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Divider()
                Toggle("显示最近使用的窗口", isOn: $settings.dockCompanionShowsRecentWindows)
                    .onChange(of: settings.dockCompanionShowsRecentWindows) { _ in onChanged() }
                Text("临时补充 5 分钟内使用过、尚未达到显示门槛的最多 2 个窗口；手动隐藏的 App 不会出现。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        HStack {
            Button {
                chooseDockCompanionApplications(for: side)
            } label: {
                Label("添加 App…", systemImage: "plus")
            }
            Spacer()
        }
        if dockCompanionApps.isEmpty {
            emptyState("当前没有可配置的 App")
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(dockCompanionApps.enumerated()), id: \.element.key) { index, app in
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
                    .toggleStyle(.checkbox)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 7)
                    if index < dockCompanionApps.count - 1 { Divider() }
                }
            }
        }
    }

    private var dockCompanionAvailableAppKeys: Set<String> {
        Set(dockCompanionApps.map(\.key))
    }

    private func chooseDockCompanionApplications(for side: DockCompanionAppSide) {
        let panel = NSOpenPanel()
        panel.title = "添加融合模式 App"
        panel.message = "选择要显示在原生 Dock \(side == .left ? "左侧" : "右侧")的 App"
        panel.prompt = "添加"
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.begin { response in
            guard response == .OK else { return }
            let available = dockCompanionAvailableAppKeys
            let addedCount = panel.urls.reduce(0) { count, url in
                count + (settings.addDockCompanionApp(
                    applicationURL: url,
                    side: side,
                    availableAppKeys: available
                ) ? 1 : 0)
            }
            if addedCount > 0 { onChanged() }
        }
    }

    private var matrixTab: some View {
        tabScrollView {
            modeHeader(
                title: "矩阵模式",
                description: "按 App 分列展示窗口，适合同时查看和切换较多窗口。",
                systemImage: SettingsTab.matrix.systemImage,
                mode: .matrix
            )

            modeVisualSettings(for: .matrix)

            settingsSection(title: "排列方式", description: "矩阵会自动根据可用宽度压缩任务项。") {
                Label("每个 App 独立成列", systemImage: "rectangle.split.3x1")
                Label("最先打开的窗口排列在底部", systemImage: "arrow.down.to.line")
                Label("可覆盖在窗口上，不调整其他窗口大小；底边贴齐屏幕", systemImage: "rectangle.on.rectangle")
                Label("按住 Option 并拖动可移动整个矩阵", systemImage: "option")
            }
        }
    }

    private func tabScrollView<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(.horizontal, 42)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func modeVisualSettings(for mode: TaskDockLayoutMode) -> some View {
        Group {
            settingsSection(title: "外观", description: "仅影响当前模式的任务项。") {
                Picker("主题", selection: Binding(
                    get: { settings.appearancePreference(in: mode) },
                    set: { settings.setAppearance($0, in: mode); onVisualChanged() }
                )) {
                    ForEach(ModeAppearance.allCases) { appearance in
                        Text(mode == .dockCompanion && appearance == .system
                             ? "跟随系统（推荐）" : appearance.label).tag(appearance)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize(horizontal: true, vertical: false)
                if mode == .dockCompanion {
                    Text("手动指定浅色或深色仅改变 TaskDock；原生 Dock 仍跟随系统，外观可能不一致。")
                        .font(.caption)
                        .foregroundStyle(settings.appearancePreference(in: mode) == .system ? Color.secondary : Color.orange)
                }
                Picker("非选中项透明度", selection: Binding(
                    get: { Int((settings.transparency(in: mode) * 100).rounded()) },
                    set: { settings.setTransparency(Double($0) / 100, in: mode); onVisualChanged() }
                )) {
                    ForEach(Array(stride(from: 0, through: 70, by: 5)), id: \.self) { percent in
                        Text("\(percent)%").tag(percent)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize(horizontal: true, vertical: false)
            }

            settingsSection(title: "窗口显示", description: "仅影响当前模式的窗口清单。") {
                Toggle("显示隐藏 App 的窗口", isOn: Binding(
                    get: { settings.showsHiddenApps(in: mode) },
                    set: { settings.setShowsHiddenApps($0, in: mode); onChanged() }
                ))
                Toggle("Finder 标签按窗口显示", isOn: Binding(
                    get: { settings.showsFinderTabsAsWindows(in: mode) },
                    set: { settings.setShowsFinderTabsAsWindows($0, in: mode); onChanged() }
                ))
                Text("开启后，Finder 每个标签单独显示为任务项；关闭时仍按原生窗口显示。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func settingsSection<Content: View>(
        title: String,
        description: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            if let description {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            content()
            Divider()
                .padding(.top, 12)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
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
                HStack(spacing: 8) {
                    Text(title).font(.title3.weight(.semibold))
                    if mode != .taskbar {
                        Text("实验功能")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.12), in: Capsule())
                    }
                }
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

    private func chooseFavoriteFolders() {
        let panel = NSOpenPanel()
        panel.title = "添加收藏文件夹"
        panel.message = "选择要显示在任务栏最右侧的文件夹"
        panel.prompt = "添加"
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.begin { response in
            guard response == .OK else { return }
            let addedCount = panel.urls.reduce(0) { count, url in
                count + (settings.addFavoriteFolder(url) ? 1 : 0)
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
