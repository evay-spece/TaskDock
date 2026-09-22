import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @StateObject private var updateChecker = UpdateChecker()
    let windows: [WindowModel]
    let onChanged: () -> Void

    private var apps: [(key: String, name: String, icon: NSImage?)] {
        let grouped = Dictionary(grouping: windows, by: { $0.appKey })
        let appKeys = Set(grouped.keys).union(settings.blacklistedAppKeys)
        return appKeys.map { key in
            if let first = grouped[key]?.first {
                return (key, first.applicationName, first.applicationIcon)
            }
            return blacklistedAppFallback(for: key)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("TaskDock 设置")
                .font(.title2.weight(.semibold))

            Picker("显示模式", selection: $settings.layoutMode) {
                ForEach(TaskDockLayoutMode.allCases) { mode in
                    Label(mode.label, systemImage: mode.systemImage)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: settings.layoutMode) { _ in onChanged() }

            Picker("主题", selection: $settings.appearance) {
                ForEach(TaskbarAppearance.allCases) { appearance in
                    Label(appearance.label, systemImage: appearance == .light ? "sun.max.fill" : "moon.fill")
                        .tag(appearance)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: settings.appearance) { _ in onChanged() }

            VStack(alignment: .leading, spacing: 8) {
                Text("任务栏位置")
                    .font(.headline)
                if settings.layoutMode == .dockCompanion {
                    Text("Dock 融合模式会自动紧接在原生 Dock 右侧。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Picker("任务栏位置", selection: $settings.taskbarAlignment) {
                    ForEach(TaskbarAlignment.allCases) { alignment in
                        Text(alignment.label).tag(alignment)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .disabled(settings.layoutMode != .taskbar)
                .onChange(of: settings.taskbarAlignment) { _ in onChanged() }
            }

            Toggle("显示隐藏 App 的窗口", isOn: $settings.showHiddenApps)
                .onChange(of: settings.showHiddenApps) { _ in onChanged() }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("隐藏/显示 TaskDock 快捷键")
                    .font(.headline)
                Text("连续按两次选定的修饰键。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("隐藏/显示 TaskDock 快捷键", selection: $settings.toggleModifier) {
                    ForEach(TaskbarToggleModifier.allCases) { modifier in
                        Text(modifier.label).tag(modifier)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            Divider()

            Text("App 黑名单")
                .font(.headline)
            Text("勾选后，该 App 的窗口不会显示在 TaskDock 中。")
                .font(.caption)
                .foregroundStyle(.secondary)

            if apps.isEmpty {
                Text("当前没有可配置的 App")
                    .foregroundStyle(.secondary)
            } else {
                List(apps, id: \.key) { app in
                    Toggle(isOn: Binding(
                        get: { settings.blacklistedAppKeys.contains(app.key) },
                        set: { _ in
                            settings.toggleBlacklist(for: app.key)
                            onChanged()
                        }
                    )) {
                        HStack(spacing: 8) {
                            Image(nsImage: app.icon ?? NSImage(size: NSSize(width: 20, height: 20)))
                                .resizable()
                                .frame(width: 20, height: 20)
                            Text(app.name)
                        }
                    }
                }
                .frame(height: blacklistHeight)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("软件更新")
                            .font(.headline)
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
        .padding(22)
        .frame(width: 380, height: 620)
    }

    private var blacklistHeight: CGFloat {
        min(max(CGFloat(apps.count) * 34, 100), 180)
    }

    private func blacklistedAppFallback(for key: String) -> (key: String, name: String, icon: NSImage?) {
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
            EmptyView()
        case .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("正在检查 GitHub Release…")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        case .upToDate(let version):
            Label("已是最新版（\(version)）", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .updateAvailable(let update):
            HStack {
                Label("发现新版本 \(update.version)", systemImage: "arrow.down.circle.fill")
                Spacer()
                Button("下载并重启") { updateChecker.downloadAndRestart(update) }
            }
            .font(.caption)
        case .downloading(let version):
            updateProgress("正在下载 TaskDock \(version)…")
        case .verifying:
            updateProgress("正在验证安装包…")
        case .installing:
            updateProgress("正在安装并重启…")
        case .failed(let message, let releaseURL):
            HStack {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                if let releaseURL {
                    Spacer()
                    Button("打开发布页") { updateChecker.openRelease(releaseURL) }
                }
            }
            .font(.caption)
        }
    }

    private func updateProgress(_ text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
