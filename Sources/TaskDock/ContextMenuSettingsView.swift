import SwiftUI
import FinderSync

struct ContextMenuSettingsView: View {
    @StateObject private var manager = ContextMenuManager()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("管理其他软件添加的右键菜单").font(.headline)
                Spacer()
                if manager.busy { ProgressView().controlSize(.small) }
                Button("刷新列表") { manager.refresh() }.disabled(manager.busy)
            }
            Text("Finder 扩展按软件整体停用，可能同时影响徽标和同步入口；服务菜单可以逐项隐藏。停用后可重新启用，也可恢复修改前的设置。")
                .font(.caption).foregroundStyle(.secondary)
            ForEach([false, true], id: \.self) { service in
                let rows = manager.items.filter { service ? $0.kind == .service : $0.kind == .finder }
                if !rows.isEmpty {
                    Divider()
                    DisclosureGroup("\(service ? "服务菜单" : "Finder 扩展")（\(rows.count)）") {
                    ForEach(rows) { item in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.name).lineLimit(2)
                                Text(service ? item.source : item.source + " · " + finderState(item))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }.help(item.path)
                            Spacer(minLength: 8)
                            if ContextMenuBackend.hasBackup(item) {
                                Button("恢复原设置") { manager.change(item, restore: true) }
                            }
                            Button(item.disabled ? "启用" : (service ? "隐藏" : "停用")) { manager.change(item) }
                        }.disabled(manager.busy)
                    }
                    }
                }
            }
            if manager.scanned && manager.items.isEmpty { Text("未发现可管理的第三方 Finder 扩展或服务菜单。").foregroundStyle(.secondary) }
            if !manager.message.isEmpty { Text(manager.message).font(.caption).foregroundStyle(.secondary) }
            Text("列表来自系统登记，实际菜单会随所选文件变化。应用自行注入的菜单、分享项及部分“快速操作”请到对应软件或系统设置中管理。这里的更改独立于 TaskDock 新建文件开关。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("打开扩展设置") { FIFinderSyncController.showExtensionManagementInterface() }
                Button("打开服务快捷键设置") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.keyboard?Services")!)
                }
            }
        }.onAppear { manager.refresh() }
    }

    private func finderState(_ item: ContextMenuProvider) -> String {
        if item.disabled { return "已停用" }
        if item.state == "+" || item.state == "!" { return "已启用" }
        return "跟随系统默认"
    }
}
