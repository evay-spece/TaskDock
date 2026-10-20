import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case taskbar
    case dockCompanion
    case feedback
    case about

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general: return "通用"
        case .taskbar: return "任务栏"
        case .dockCompanion: return "融合模式"
        case .feedback: return "用户反馈"
        case .about: return "关于"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .taskbar: return "rectangle.bottomthird.inset.filled"
        case .dockCompanion: return "dock.rectangle"
        case .feedback: return "bubble.left.and.bubble.right"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var license: LicenseService
    @ObservedObject private var updateChecker = UpdateChecker.shared
    @State private var selectedTab: SettingsTab = .general
    @AppStorage("feedbackDraftTitle") private var feedbackTitle = ""
    @AppStorage("feedbackDraftDetails") private var feedbackDetails = ""
    @State private var feedbackOpenFailed = false
    @State private var feedbackCopied = false
    let windows: [WindowModel]
    let onChanged: () -> Void
    let onVisualChanged: () -> Void
    let onLayoutChanged: () -> Void
    let onOpenLicense: () -> Void

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
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(SettingsTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: tab.systemImage)
                                .font(.system(size: 17, weight: .medium))
                                .frame(width: 23)
                            Text(tab.label)
                                .font(.system(size: 14, weight: selectedTab == tab ? .semibold : .medium))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.primary)
                        .padding(.horizontal, 15)
                        .frame(height: 45)
                        .background(
                            selectedTab == tab ? Color.accentColor.opacity(0.15) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 11)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 11))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 65)
            .padding(.bottom, 16)
            .frame(width: 208)
            .background(Color(nsColor: .textBackgroundColor))

            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1)

            Group {
                switch selectedTab {
                case .general: generalTab
                case .taskbar: taskbarTab
                case .dockCompanion: dockCompanionTab
                case .feedback: feedbackTab
                case .about: aboutTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 850, minHeight: 620)
    }

    private var feedbackTab: some View {
        tabScrollView {
            settingsSection(title: "提建议或报告问题", description: "通过腾讯问卷反馈建议或问题，也可以先在这里整理草稿。") {
                VStack(alignment: .leading, spacing: 12) {
                    if feedbackURL == nil {
                        Label("反馈表单暂未开放", systemImage: "info.circle")
                            .foregroundStyle(.secondary)
                        Text("目前尚未配置腾讯问卷，暂时无法提交。你可以先保存草稿或复制内容。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("点击下方按钮在浏览器打开腾讯问卷，在问卷中填写并确认提交。这里的草稿不会自动上传，请按需复制粘贴。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Text("反馈草稿（可选）")
                    TextField("标题（最多 120 字）", text: $feedbackTitle)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: feedbackTitle) { value in
                            feedbackTitle = String(value.prefix(120))
                            feedbackCopied = false
                        }
                    Text("详细内容")
                    TextEditor(text: $feedbackDetails)
                        .font(.body)
                        .frame(minHeight: 150)
                        .padding(4)
                        .background(Color(nsColor: .textBackgroundColor))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.15)))
                        .accessibilityLabel("反馈详细内容")
                        .onChange(of: feedbackDetails) { value in
                            feedbackDetails = String(value.prefix(2000))
                            feedbackCopied = false
                        }
                    Text("\(feedbackDetails.count)/2000 字")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("请勿填写密码、激活码或其他隐私信息。复制内容包含下方版本信息，方便定位问题。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(feedbackEnvironment)
                        .font(.caption)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                    Text("草稿会保存在本机，关闭设置后可继续编辑。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("打开腾讯问卷…") {
                            guard let url = feedbackURL else { return }
                            feedbackOpenFailed = !NSWorkspace.shared.open(url)
                        }
                        .disabled(feedbackURL == nil)
                        Button(feedbackCopied ? "已复制" : "复制反馈内容") {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            feedbackCopied = pasteboard.setString(FeedbackDraft.copyText(title: feedbackTitle, details: feedbackDetails, environment: feedbackEnvironment), forType: .string)
                        }
                    }
                    if feedbackOpenFailed {
                        Text("未能打开浏览器，请重试。当前填写的内容已保留。")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    private var feedbackURL: URL? {
        FeedbackDraft.configuredFormURL
    }

    private var feedbackEnvironment: String {
        FeedbackDraft.environment(
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知",
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "未知",
            systemVersion: ProcessInfo.processInfo.operatingSystemVersionString
        )
    }

    private var generalTab: some View {
        tabScrollView {
            settingsSection(title: "购买与激活", description: "7 天完整试用，¥59 一次购买授权；人工核款后通过邮件发码。") {
                HStack {
                    Text((license.activatedLicenseCode.isEmpty && !LicenseStatus.hasValidPurchase) ?
                        (license.isUnlocked ? "试用剩余 \(license.remainingDays) 天" : "试用已结束") : "已购买授权")
                    Spacer()
                    Button("购买与激活…", action: onOpenLicense)
                }
            }
            settingsSection(title: "显示模式", description: "选择 TaskDock 当前使用的模式；窗口显示在各模式中分别设置。") {
                HStack {
                    Text("显示模式")
                    Spacer()
                    Picker("显示模式", selection: $settings.layoutMode) {
                        ForEach(TaskDockLayoutMode.allCases) { mode in
                            Label(mode.label, systemImage: mode.systemImage).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize(horizontal: true, vertical: false)
                    .onChange(of: settings.layoutMode) { _ in onChanged() }
                }
            }

            settingsSection(title: "任务项外观", description: "设置窗口卡片的高亮颜色。") {
                HStack {
                    Text("任务项高亮颜色")
                    Spacer()
                    Picker("任务项高亮颜色", selection: $settings.taskItemHighlightStyle) {
                        ForEach(TaskItemHighlightStyle.allCases) { style in
                            Text(style.label).tag(style)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize(horizontal: true, vertical: false)
                    .onChange(of: settings.taskItemHighlightStyle) { _ in onVisualChanged() }
                }
            }

            settingsSection(title: "隐藏/显示快捷键", description: "连续按两次选定的修饰键。") {
                HStack {
                    Text("快捷键")
                    Spacer()
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
            }

            settingsSection(
                title: "App 黑名单",
                description: "开启后，该 App 的全部窗口都不会显示在 TaskDock 中。"
            ) {
                if apps.isEmpty {
                    emptyState("当前没有可配置的 App")
                } else {
                    VStack(spacing: 8) {
                        ForEach(apps, id: \.key) { app in
                            settingsToggle(
                                title: app.name,
                                description: "不在 TaskDock 中显示此 App 的窗口。",
                                icon: app.icon ?? fallbackIcon,
                                isOn: Binding(
                                get: { settings.blacklistedAppKeys.contains(app.key) },
                                set: { _ in
                                    settings.toggleBlacklist(for: app.key)
                                    onChanged()
                                }
                                )
                            )
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

        }
    }

    private var aboutTab: some View {
        tabScrollView {
            settingsSection(title: "TaskDock", description: "版本 \(updateChecker.currentVersion)") {
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("TaskDock")
                            .font(.title2.weight(.bold))
                        Text("让窗口切换更顺手")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }

            settingsSection(title: "软件更新") {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("检查更新")
                            .font(.system(size: 14, weight: .medium))
                        Text("当前版本 \(updateChecker.currentVersion)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("检查更新") { updateChecker.check() }
                        .disabled(isChecking)
                }
                updateStatusView
            }
        }
    }

    private var taskbarTab: some View {
        tabScrollView {
            modeHeader(
                title: "任务栏模式",
                description: "显示所有可用窗口，并支持收藏 App 和拖动排序。",
                systemImage: SettingsTab.taskbar.systemImage,
                mode: .taskbar
            )

            modeVisualSettings(for: .taskbar)

            settingsSection(title: "位置与尺寸", description: "调整任务栏留白、高度和收藏图标放大倍率。") {
                HStack {
                    Label("任务栏两侧留白", systemImage: "arrow.left.and.right")
                    Spacer()
                    Text("\(Int(settings.taskbarSideInset.rounded())) pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: $settings.taskbarSideInset, in: SettingsStore.taskbarSideInsetRange, step: 1)
                    .accessibilityLabel("任务栏两侧留白")
                    .onChange(of: settings.taskbarSideInset) { _ in onLayoutChanged() }
                Text("向右拖动，两侧同步向内收缩；实时生效并自动保存。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                    Label("图标放大倍率", systemImage: "arrow.up.left.and.arrow.down.right")
                    Spacer()
                    Text(String(format: "%.1f×", Double(settings.favoriteMagnificationScale)))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: $settings.favoriteMagnificationScale, in: 1.2...2.4, step: 0.1)
                    .accessibilityLabel("图标放大倍率")
                    .disabled(!settings.favoriteMagnificationEnabled)
                    .onChange(of: settings.favoriteMagnificationScale) { _ in onLayoutChanged() }
                HStack {
                    Label("任务项文字大小", systemImage: "textformat.size")
                    Spacer()
                    Text("\(Int(settings.taskbarItemFontSize.rounded())) pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("字号")
                    Spacer()
                    Picker("任务项文字大小", selection: $settings.taskbarItemFontSize) {
                        ForEach(SettingsStore.taskbarItemFontSizes, id: \.self) { size in
                            Text("\(Int(size))").tag(size)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize(horizontal: true, vertical: false)
                    .onChange(of: settings.taskbarItemFontSize) { _ in onVisualChanged() }
                }
                Text("仅调整任务栏任务项文字，共 5 档；默认 12 pt。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            settingsSection(title: "快捷键", description: "任务栏显示期间可直接使用；按下 Option 显示对应提示。") {
                Text("⌥ + D：全局最小化窗口；再按一次恢复这次最小化的窗口。")
                    .font(.caption)
                Text("⌥ + J/K/L/;/'/N/M/,/.：从左到右的前 9 个窗口任务项。")
                    .font(.caption)
                Text("⌥ + 1–9：从左到右的前 9 个收藏 App。再次按相同快捷键可最小化当前窗口。")
                    .font(.caption)
            }

            settingsSection(title: "任务项与动画", description: "只影响任务栏模式。") {
                HStack {
                    Text("任务项长度")
                    Spacer()
                    Picker("任务项长度", selection: $settings.taskbarItemWidthMode) {
                        ForEach(TaskbarItemWidthMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize(horizontal: true, vertical: false)
                    .onChange(of: settings.taskbarItemWidthMode) { _ in onLayoutChanged() }
                }
                Text("固定长度：所有任务项等宽。自适应长度：按标题长短分配，最长不超过原固定长度。空间不足时可横向滚动。")
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                settingsToggle(
                    title: "同一 App 有 3 个及以上窗口时折叠",
                    description: "点击折叠的任务项可选择具体窗口；1–2 个窗口仍分别显示。",
                    isOn: $settings.taskbarCollapseSameAppWindows
                )
                    .onChange(of: settings.taskbarCollapseSameAppWindows) { _ in onLayoutChanged() }
            }

            settingsSection(title: "收藏栏来源", description: "选择 TaskDock 独立收藏，或与系统 Dock 的固定项目保持同步。") {
                settingsToggle(
                    title: "收藏栏同步系统 Dock",
                    description: "同步系统 Dock 的固定 App、文件夹及当前显示的临时 App；固定项目在任一边调整都会同步。Finder 始终保留。",
                    isOn: Binding(
                        get: { settings.dockFavoritesSyncEnabled },
                        set: { settings.setDockFavoritesSyncEnabled($0); onChanged() }
                    )
                )
                if let error = settings.dockFavoritesSyncError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
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
                settingsToggle(
                    title: "收藏图标悬停反馈",
                    description: "鼠标移到收藏图标上时弹性放大；关闭后保持固定大小。",
                    isOn: $settings.favoriteMagnificationEnabled
                )
                    .onChange(of: settings.favoriteMagnificationEnabled) { _ in onVisualChanged() }
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
                                .disabled(settings.dockFavoritesSyncEnabled
                                    && favorite.bundleIdentifier == "com.apple.finder")
                            }
                            .padding(.vertical, 7)
                            if index < settings.favoriteApps.count - 1 { Divider() }
                        }
                    }
                }
            }

            settingsSection(title: "收藏文件夹", description: "显示在收藏栏分隔线后、废纸篓左侧；点击图标会在 Finder 中打开。") {
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
                Text("⌥ + D：全局最小化窗口；再按一次恢复这次最小化的窗口。")
                    .font(.caption)
                Text("左侧窗口：⌥ + 1–8；右侧窗口：⌥ + J/K/L/;/'。")
                    .font(.caption)
                Text("按一次切换或恢复窗口；焦点已在该窗口时，再按一次将其最小化。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            settingsSection(title: "窗口与栏位", description: "设置融合栏显示条件和底栏外观。Finder 不受窗口数量门槛限制。") {
                HStack {
                    Text("至少需要的窗口数")
                    Spacer()
                    Picker("至少需要的窗口数", selection: Binding(
                        get: { settings.dockCompanionMinimumWindowCount },
                        set: { settings.dockCompanionMinimumWindowCount = min(max($0, 1), 20) }
                    )) {
                        ForEach(1...20, id: \.self) { count in
                            Text("\(count) 个").tag(count)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize(horizontal: true, vertical: false)
                    .onChange(of: settings.dockCompanionMinimumWindowCount) { _ in onChanged() }
                }
                Divider()
                HStack {
                    Text("App 窗口折叠门槛")
                    Spacer()
                    Picker("App 窗口折叠门槛", selection: Binding(
                        get: { settings.dockCompanionCollapseThreshold },
                        set: { settings.dockCompanionCollapseThreshold = min(max($0, 2), 20) }
                    )) {
                        ForEach(2...20, id: \.self) { count in
                            Text("\(count) 个").tag(count)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize(horizontal: true, vertical: false)
                    .onChange(of: settings.dockCompanionCollapseThreshold) { _ in onChanged() }
                }
                Text("达到门槛后只占一个位置；点击 App 入口可选择具体窗口。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Divider()
                settingsToggle(
                    title: "显示最近使用的窗口",
                    description: "临时补充 5 分钟内使用过、未达显示门槛的最多 2 个窗口；手动隐藏的 App 不会出现。",
                    isOn: $settings.dockCompanionShowsRecentWindows
                )
                    .onChange(of: settings.dockCompanionShowsRecentWindows) { _ in onChanged() }
                settingsToggle(
                    title: "显示底栏",
                    description: "关闭后隐藏底栏背景和功能按钮，只显示任务项；任务项高度与 Dock 一致。",
                    isOn: $settings.dockCompanionShowsBottomBar
                )
                    .onChange(of: settings.dockCompanionShowsBottomBar) { _ in onChanged() }
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

            settingsSection(title: "Dock 覆盖实验") {
                settingsToggle(
                    title: "叠加到 Dock 图标区（实验）",
                    description: "Finder 叠在 Dock 左端，其他任务项叠在右端；关闭后恢复原融合布局。",
                    isOn: $settings.dockCompanionOverlayEnabled
                )
                    .onChange(of: settings.dockCompanionOverlayEnabled) { _ in onChanged() }
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
            VStack(alignment: .leading, spacing: 8) {
                ForEach(dockCompanionApps, id: \.key) { app in
                    settingsToggle(
                        title: app.name,
                        description: side == .left
                            ? "在原生 Dock 左侧显示此 App 的窗口。"
                            : "在原生 Dock 右侧显示此 App 的窗口。",
                        icon: app.icon ?? fallbackIcon,
                        isOn: Binding(
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
                        )
                    )
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

    private func tabScrollView<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(selectedTab.label)
                    .font(.system(size: 24, weight: .bold))
                    .padding(.bottom, 10)
                content()
            }
            .padding(.horizontal, 30)
            .padding(.top, 54)
            .padding(.bottom, 30)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func modeVisualSettings(for mode: TaskDockLayoutMode) -> some View {
        Group {
            settingsSection(title: "任务项透明度", description: "仅影响当前模式的任务项。") {
                HStack {
                    Text("非选中项透明度")
                    Spacer()
                    Picker("非选中项透明度", selection: Binding(
                        get: { Int((settings.transparency(in: mode) * 100).rounded()) },
                        set: { settings.setTransparency(Double($0) / 100, in: mode); onVisualChanged() }
                    )) {
                        ForEach(Array(stride(from: 0, through: 70, by: 5)), id: \.self) { percent in
                            Text("\(percent)%").tag(percent)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize(horizontal: true, vertical: false)
                }
            }

            settingsSection(title: "窗口显示", description: "仅影响当前模式的窗口清单。") {
                settingsToggle(
                    title: "显示隐藏 App 的窗口",
                    description: "将被 macOS 隐藏的 App 窗口也列入当前模式。",
                    isOn: Binding(
                        get: { settings.showsHiddenApps(in: mode) },
                        set: { settings.setShowsHiddenApps($0, in: mode); onChanged() }
                    )
                )
                settingsToggle(
                    title: "Finder 标签按窗口显示",
                    description: "开启后每个 Finder 标签单独显示；关闭时按原生窗口显示。",
                    isOn: Binding(
                        get: { settings.showsFinderTabsAsWindows(in: mode) },
                        set: { settings.setShowsFinderTabsAsWindows($0, in: mode); onChanged() }
                    )
                )
            }
        }
    }

    private func settingsToggle(
        title: String,
        description: String,
        icon: NSImage? = nil,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 12) {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 24, height: 24)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(.accentColor)
                .accessibilityLabel(title)
                .accessibilityHint(description)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
    }

    private func settingsSection<Content: View>(
        title: String,
        description: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .padding(.leading, 4)
            if let description {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 17))
            .overlay {
                RoundedRectangle(cornerRadius: 17)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            }
        }
        .padding(.bottom, 15)
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
            HStack(spacing: 8) {
                if let progress = updateChecker.downloadProgress {
                    ProgressView(value: progress).frame(width: 110)
                    Text("正在下载 \(version) \(Int(progress * 100))%")
                } else {
                    ProgressView().frame(width: 110)
                    Text("正在下载 \(version)…")
                }
            }
            .font(.caption)
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
