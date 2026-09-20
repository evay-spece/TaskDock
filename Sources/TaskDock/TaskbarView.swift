import SwiftUI

struct TaskbarView: View {
    let windows: [WindowModel]
    let isAccessibilityTrusted: Bool
    let onRequestPermission: () -> Void
    let onRefresh: () -> Void
    let onSelect: (WindowModel) -> Void
    let onShowAppWindows: (WindowModel) -> Void
    let onClose: (WindowModel) -> Void
    @ObservedObject var settings: SettingsStore
    let onSettingsChanged: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 8) {
                if !isAccessibilityTrusted {
                    permissionView
                    Spacer(minLength: 0)
                } else if windows.isEmpty {
                    Text("没有可显示的窗口")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                    Spacer(minLength: 0)
                } else {
                    let itemWidth = taskItemWidth(for: geometry.size.width)
                    HStack(spacing: 6) {
                        ForEach(windows) { window in
                            Button { onSelect(window) } label: {
                                WindowTaskItemView(window: window, availableWidth: itemWidth, onShowAppWindows: { onShowAppWindows(window) }, onClose: { onClose(window) })
                            }
                            .buttonStyle(.plain)
                            .frame(width: itemWidth)
                            .contextMenu {
                                Button("显示该 App 的所有窗口") { onShowAppWindows(window) }
                                Divider()
                                Button("关闭此窗口", role: .destructive) { onClose(window) }
                            }
                        }
                    }
                    .padding(.leading, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 12) {
                    Button(action: onRefresh) { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.plain)
                        .help("刷新窗口")
                    Button(action: onOpenSettings) { Image(systemName: "gearshape") }
                        .buttonStyle(.plain)
                        .help("TaskDock 设置")
                }
                .padding(.trailing, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.16)))
        .padding(4)
        .preferredColorScheme(settings.appearance.colorScheme)
    }

    private func taskItemWidth(for totalWidth: CGFloat) -> CGFloat {
        guard !windows.isEmpty else { return 0 }
        let controlsAndPadding: CGFloat = 92
        let totalSpacing = CGFloat(max(windows.count - 1, 0)) * 6
        let available = max(totalWidth - controlsAndPadding - totalSpacing, 0)
        return min(240, max(30, available / CGFloat(windows.count)))
    }

    private var permissionView: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield")
            Text("需要“辅助功能”权限才能读取和切换窗口")
            Button("打开设置") { onRequestPermission() }
                .buttonStyle(.borderedProminent)
        }
        .padding(.leading, 14)
    }
}

struct WindowTaskItemView: View {
    let window: WindowModel
    let availableWidth: CGFloat
    let onShowAppWindows: () -> Void
    let onClose: () -> Void
    @State private var isHovered = false
    @State private var showingLongPressMenu = false

    var body: some View {
        HStack(spacing: availableWidth < 72 ? 0 : 7) {
            Image(nsImage: window.applicationIcon ?? fallbackIcon)
                .resizable()
                .frame(width: iconSize, height: iconSize)
            if availableWidth >= 72 {
                VStack(alignment: .leading, spacing: 1) {
                    Text(window.title)
                        .font(availableWidth < 118 ? .caption : .body)
                        .lineLimit(1)
                    if availableWidth >= 132 {
                        Text(window.applicationName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if window.isMinimized && availableWidth >= 116 {
                Image(systemName: "minus.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help("此窗口已最小化")
            }
        }
        .padding(.horizontal, availableWidth < 72 ? 3 : 9)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: availableWidth < 72 ? .center : .leading)
        .background(itemBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(itemBorder, lineWidth: isHovered ? 2 : (window.isFocused ? 1.5 : 0)))
        .overlay(alignment: .bottom) {
            if window.isFocused {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(height: 3)
                    .padding(.horizontal, 9)
                    .padding(.bottom, 2)
            }
        }
        .scaleEffect(isHovered ? 1.035 : 1.0)
        .shadow(color: isHovered ? Color.accentColor.opacity(0.35) : .clear, radius: 9, y: 3)
        .zIndex(isHovered ? 2 : (window.isFocused ? 1 : 0))
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .onHover { isHovered = $0 }
        .help("点击切换到此窗口；右键查看更多操作")
        .onLongPressGesture(minimumDuration: 0.5) { showingLongPressMenu = true }
        .popover(isPresented: $showingLongPressMenu, arrowEdge: .bottom) {
            WindowActionMenu(onShowAppWindows: { showingLongPressMenu = false; onShowAppWindows() }, onClose: { showingLongPressMenu = false; onClose() })
        }
    }

    private var fallbackIcon: NSImage {
        NSImage(named: NSImage.applicationIconName) ?? NSImage(size: NSSize(width: 24, height: 24))
    }

    private var itemBackground: Color {
        if window.isFocused { return Color.accentColor.opacity(0.42) }
        if isHovered { return Color.accentColor.opacity(0.16) }
        return Color.primary.opacity(0.06)
    }

    private var itemBorder: Color {
        if window.isFocused { return Color.accentColor.opacity(0.95) }
        if isHovered { return Color.accentColor.opacity(0.85) }
        return .clear
    }

    private var iconSize: CGFloat {
        availableWidth < 48 ? 20 : 24
    }
}

private struct WindowActionMenu: View {
    let onShowAppWindows: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button("显示该 App 的所有窗口", action: onShowAppWindows)
            Divider()
            Button("关闭此窗口", role: .destructive, action: onClose)
        }
        .padding(10)
    }
}
