import AppKit
import SwiftUI

struct TaskbarView: View {
    let windows: [WindowModel]
    let isAccessibilityTrusted: Bool
    let onRequestPermission: () -> Void
    let onSelect: (WindowModel) -> Void
    let onMinimizeAll: () -> Void
    let onShowAppWindows: (WindowModel) -> Void
    let onClose: (WindowModel) -> Void
    @ObservedObject var settings: SettingsStore
    let onSettingsChanged: () -> Void
    let onOpenSettings: () -> Void
    let onAppDragChanged: (Bool) -> Void
    let onPanelDragChanged: (CGSize) -> Void
    let onPanelDragEnded: () -> Void
    let onHideTaskbar: () -> Void
    let onQuit: () -> Void
    @State private var draggedAppKey: String?
    @State private var dragTranslation: CGFloat = 0
    @State private var dragStartAppKeys: [String]?
    @State private var hoverTargetAppKey: String?
    @State private var dragDirection: AppDragDirection?
    @State private var isOptionMovingPanel = false

    var body: some View {
        Group {
            switch settings.layoutMode {
            case .taskbar:
                taskbarView
            case .matrix:
                matrixView
            }
        }
        .preferredColorScheme(settings.appearance.colorScheme)
        .simultaneousGesture(optionPanelMoveGesture)
    }

    private var matrixView: some View {
        GeometryReader { geometry in
            HStack(alignment: .bottom, spacing: 6) {
                if !isAccessibilityTrusted {
                    permissionView
                } else if windows.isEmpty {
                    Text("没有可显示的窗口")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12)))
                } else {
                    let columnWidth = appColumnWidth(for: geometry.size.width)
                    ScrollView(.vertical, showsIndicators: false) {
                        HStack(alignment: .bottom, spacing: 6) {
                            ForEach(appGroups) { group in
                                VStack(spacing: 2) {
                                    ForEach(Array(group.windows.reversed())) { window in
                                        WindowTaskItemView(
                                            window: window,
                                            availableWidth: columnWidth,
                                            appearance: settings.appearance,
                                            onShowAppWindows: { onShowAppWindows(window) },
                                            onClose: { onClose(window) }
                                        )
                                        .id(window.renderStateID)
                                        .frame(width: columnWidth, height: 35)
                                        .contentShape(Rectangle())
                                        .onTapGesture { onSelect(window) }
                                        .simultaneousGesture(appReorderGesture(for: window, columnWidth: columnWidth))
                                        .contextMenu {
                                            Button("显示该 App 的所有窗口") { onShowAppWindows(window) }
                                            Divider()
                                            Button("关闭此窗口", role: .destructive) { onClose(window) }
                                        }
                                        .accessibilityElement(children: .combine)
                                        .accessibilityAddTraits(.isButton)
                                        .accessibilityValue(window.isFocused ? "当前焦点窗口" : "非焦点窗口")
                                        .accessibilityAction { onSelect(window) }
                                    }
                                }
                                .frame(width: columnWidth, alignment: .bottom)
                                .offset(x: appColumnOffset(for: group.id, columnWidth: columnWidth))
                                .animation(draggedAppKey == group.id ? nil : .easeOut(duration: 0.16), value: hoverTargetAppKey)
                                .animation(draggedAppKey == group.id ? nil : .easeOut(duration: 0.16), value: dragDirection)
                                .opacity(draggedAppKey == group.id ? 0.88 : 1)
                                .scaleEffect(isDropTarget(group.id) ? 0.98 : 1)
                                .overlay {
                                    if isDropTarget(group.id) {
                                        RoundedRectangle(cornerRadius: 9)
                                            .stroke(Color.accentColor.opacity(0.72), lineWidth: 1.5)
                                    }
                                }
                                .shadow(color: isDropTarget(group.id) ? Color.accentColor.opacity(0.2) : .clear, radius: 5)
                                .zIndex(draggedAppKey == group.id ? 20 : 0)
                            }
                        }
                        .frame(
                            maxWidth: .infinity,
                            minHeight: max(0, geometry.size.height - 4),
                            alignment: .bottomTrailing
                        )
                        .padding(2)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
                matrixControls
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .padding(2)
    }

    private var taskbarView: some View {
        GeometryReader { geometry in
            HStack(spacing: 8) {
                if !isAccessibilityTrusted {
                    HStack(spacing: 10) {
                        Image(systemName: "lock.shield")
                        Text("需要“辅助功能”权限才能读取和切换窗口")
                        Button("打开设置", action: onRequestPermission)
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(.leading, 14)
                    taskbarDragArea
                } else if windows.isEmpty {
                    Text("没有可显示的窗口")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                    taskbarDragArea
                } else {
                    let itemWidth = taskbarItemWidth(for: geometry.size.width)
                    HStack(spacing: 4) {
                        ForEach(orderedWindows) { window in
                            WindowTaskItemView(
                                window: window,
                                availableWidth: itemWidth,
                                appearance: settings.appearance,
                                onShowAppWindows: { onShowAppWindows(window) },
                                onClose: { onClose(window) }
                            )
                            .id(window.renderStateID)
                            .frame(width: itemWidth, height: 38)
                            .offset(x: taskbarItemOffset(for: window.appKey, itemWidth: itemWidth))
                            .animation(draggedAppKey == window.appKey ? nil : .easeOut(duration: 0.16), value: hoverTargetAppKey)
                            .animation(draggedAppKey == window.appKey ? nil : .easeOut(duration: 0.16), value: dragDirection)
                            .opacity(draggedAppKey == window.appKey ? 0.88 : 1)
                            .scaleEffect(isDropTarget(window.appKey) ? 0.98 : 1)
                            .overlay {
                                if isDropTarget(window.appKey) {
                                    RoundedRectangle(cornerRadius: 7)
                                        .stroke(Color.accentColor.opacity(0.72), lineWidth: 1.5)
                                }
                            }
                            .zIndex(draggedAppKey == window.appKey ? 20 : 0)
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect(window) }
                            .simultaneousGesture(taskbarReorderGesture(for: window, itemWidth: itemWidth))
                            .contextMenu {
                                Button("显示该 App 的所有窗口") { onShowAppWindows(window) }
                                Divider()
                                Button("关闭此窗口", role: .destructive) { onClose(window) }
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityValue(window.isFocused ? "当前焦点窗口" : "非焦点窗口")
                            .accessibilityAction { onSelect(window) }
                        }
                    }
                    .padding(.leading, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }

                HStack(spacing: 3) {
                    TaskbarControlButton(systemImage: "rectangle.grid.2x2", help: "切换到窗口矩阵", action: toggleLayoutMode)
                    TaskbarControlButton(systemImage: "minus.rectangle", help: "最小化全部窗口", action: onMinimizeAll)
                    TaskbarControlButton(systemImage: "gearshape", help: "TaskDock 设置", action: onOpenSettings)
                    TaskbarControlButton(systemImage: "arrow.down.to.line", help: "隐藏 TaskDock", action: onHideTaskbar)
                    TaskbarControlButton(systemImage: "power", help: "退出 TaskDock", action: onQuit)
                }
                .padding(.horizontal, 8)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 10).fill(taskbarSurfaceColor))
        }
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(taskbarBorderColor))
        .padding(2)
    }

    private func taskbarItemWidth(for totalWidth: CGFloat) -> CGFloat {
        guard !windows.isEmpty else { return 0 }
        let controlsAndPadding: CGFloat = 184
        let totalSpacing = CGFloat(max(windows.count - 1, 0)) * 4
        let available = max(totalWidth - controlsAndPadding - totalSpacing, 0)
        return min(240, max(30, available / CGFloat(windows.count)))
    }

    private var taskbarSurfaceColor: Color {
        settings.appearance == .dark ? Color.black.opacity(0.28) : Color.white.opacity(0.64)
    }

    private var taskbarBorderColor: Color {
        settings.appearance == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.12)
    }

    private var taskbarDragArea: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { onPanelDragChanged($0.translation) }
                    .onEnded { _ in onPanelDragEnded() }
            )
            .help("拖动任务栏")
            .accessibilityLabel("任务栏拖动区")
    }

    private func appColumnWidth(for totalWidth: CGFloat) -> CGFloat {
        let count = max(appGroups.count, 1)
        let controlAndSpacing: CGFloat = 160 + CGFloat(max(count - 1, 0)) * 6
        return min(180, max(92, (totalWidth - controlAndSpacing) / CGFloat(count)))
    }

    private var orderedWindows: [WindowModel] {
        let order = Dictionary(
            settings.appOrder.enumerated().map { ($1, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return windows.enumerated().sorted { lhs, rhs in
            let lhsOrder = order[lhs.element.appKey] ?? Int.max
            let rhsOrder = order[rhs.element.appKey] ?? Int.max
            return lhsOrder == rhsOrder ? lhs.offset < rhs.offset : lhsOrder < rhsOrder
        }.map(\.element)
    }

    private var permissionView: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield")
            Text("需要“辅助功能”权限才能读取和切换窗口")
            Button("打开设置") { onRequestPermission() }
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.12)))
    }

    private var matrixControls: some View {
        HStack(spacing: 3) {
            TaskbarControlButton(systemImage: "rectangle.bottomthird.inset.filled", help: "切换到任务栏", action: toggleLayoutMode)
            TaskbarControlButton(systemImage: "minus.rectangle", help: "最小化全部窗口", action: onMinimizeAll)
            TaskbarControlButton(systemImage: "gearshape", help: "TaskDock 设置", action: onOpenSettings)
            TaskbarControlButton(systemImage: "arrow.down.to.line", help: "隐藏窗口矩阵", action: onHideTaskbar)
            TaskbarControlButton(systemImage: "power", help: "退出 TaskDock", action: onQuit)
        }
        .padding(3)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    private func toggleLayoutMode() {
        settings.layoutMode = settings.layoutMode == .taskbar ? .matrix : .taskbar
        onSettingsChanged()
    }

    private var optionPanelMoveGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard NSEvent.modifierFlags.contains(.option) else { return }
                isOptionMovingPanel = true
                onPanelDragChanged(value.translation)
            }
            .onEnded { _ in
                guard isOptionMovingPanel else { return }
                isOptionMovingPanel = false
                onPanelDragEnded()
            }
    }

    private var appGroups: [AppWindowGroup] {
        let grouped = Dictionary(grouping: orderedWindows, by: \.appKey)
        var seen = Set<String>()
        return orderedWindows.compactMap { window in
            guard seen.insert(window.appKey).inserted,
                  let groupedWindows = grouped[window.appKey] else { return nil }
            return AppWindowGroup(id: window.appKey, windows: groupedWindows)
        }
    }

    private func appReorderGesture(for window: WindowModel, columnWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard !NSEvent.modifierFlags.contains(.option) else { return }
                if draggedAppKey == nil {
                    let groups = appGroupLayout(columnWidth: columnWidth)
                    guard groups.keys.contains(window.appKey) else { return }
                    draggedAppKey = window.appKey
                    dragStartAppKeys = groups.keys
                    onAppDragChanged(true)
                }

                guard draggedAppKey == window.appKey else { return }

                dragTranslation = value.translation.width
                let groups = appGroupLayout(columnWidth: columnWidth)
                updateDropTarget(in: groups)
            }
            .onEnded { _ in
                guard draggedAppKey == window.appKey else { return }
                if let sourceKey = draggedAppKey,
                   let targetKey = hoverTargetAppKey,
                   let dragDirection,
                   var keys = dragStartAppKeys,
                   let sourceIndex = keys.firstIndex(of: sourceKey) {
                    keys.remove(at: sourceIndex)
                    if let targetIndex = keys.firstIndex(of: targetKey) {
                        let insertionIndex = dragDirection == .left ? targetIndex : targetIndex + 1
                        keys.insert(sourceKey, at: min(insertionIndex, keys.count))
                        settings.applyVisibleAppOrder(keys)
                    }
                }
                draggedAppKey = nil
                dragTranslation = 0
                dragStartAppKeys = nil
                hoverTargetAppKey = nil
                dragDirection = nil
                onAppDragChanged(false)
            }
    }

    private func taskbarReorderGesture(for window: WindowModel, itemWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard !NSEvent.modifierFlags.contains(.option) else { return }
                if draggedAppKey == nil {
                    let groups = taskbarAppGroupLayout(itemWidth: itemWidth)
                    guard groups.keys.contains(window.appKey) else { return }
                    draggedAppKey = window.appKey
                    dragStartAppKeys = groups.keys
                    onAppDragChanged(true)
                }

                guard draggedAppKey == window.appKey else { return }
                dragTranslation = value.translation.width
                updateDropTarget(in: taskbarAppGroupLayout(itemWidth: itemWidth))
            }
            .onEnded { _ in
                guard draggedAppKey == window.appKey else { return }
                finishAppReorder()
            }
    }

    private func finishAppReorder() {
        if let sourceKey = draggedAppKey,
           let targetKey = hoverTargetAppKey,
           let dragDirection,
           var keys = dragStartAppKeys,
           let sourceIndex = keys.firstIndex(of: sourceKey) {
            keys.remove(at: sourceIndex)
            if let targetIndex = keys.firstIndex(of: targetKey) {
                let insertionIndex = dragDirection == .left ? targetIndex : targetIndex + 1
                keys.insert(sourceKey, at: min(insertionIndex, keys.count))
                settings.applyVisibleAppOrder(keys)
            }
        }
        draggedAppKey = nil
        dragTranslation = 0
        dragStartAppKeys = nil
        hoverTargetAppKey = nil
        dragDirection = nil
        onAppDragChanged(false)
    }

    private func updateDropTarget(in groups: AppGroupLayout) {
        guard let sourceKey = draggedAppKey,
              let sourceIndex = groups.keys.firstIndex(of: sourceKey),
              dragTranslation != 0 else {
            hoverTargetAppKey = nil
            dragDirection = nil
            return
        }

        let direction: AppDragDirection = dragTranslation < 0 ? .left : .right
        let targetIndex: Int?

        if direction == .left {
            let draggedLeadingEdge = groups.minXs[sourceIndex] + dragTranslation
            targetIndex = groups.keys.indices
                .filter { $0 < sourceIndex }
                .filter {
                    let width = groups.maxXs[$0] - groups.minXs[$0]
                    return draggedLeadingEdge <= groups.minXs[$0] + width * 0.25
                }
                .min()
        } else {
            let draggedTrailingEdge = groups.maxXs[sourceIndex] + dragTranslation
            targetIndex = groups.keys.indices
                .filter { $0 > sourceIndex }
                .filter {
                    let width = groups.maxXs[$0] - groups.minXs[$0]
                    return draggedTrailingEdge >= groups.maxXs[$0] - width * 0.25
                }
                .max()
        }

        hoverTargetAppKey = targetIndex.map { groups.keys[$0] }
        dragDirection = hoverTargetAppKey == nil ? nil : direction
    }

    private func appColumnOffset(for appKey: String, columnWidth: CGFloat) -> CGFloat {
        if appKey == draggedAppKey { return dragTranslation }
        guard appKey == hoverTargetAppKey, let dragDirection else { return 0 }
        return (dragDirection == .left ? 1 : -1) * columnWidth * 0.2
    }

    private func taskbarItemOffset(for appKey: String, itemWidth: CGFloat) -> CGFloat {
        if appKey == draggedAppKey { return dragTranslation }
        guard appKey == hoverTargetAppKey, let dragDirection else { return 0 }
        return (dragDirection == .left ? 1 : -1) * itemWidth * 0.2
    }

    private func isDropTarget(_ appKey: String) -> Bool {
        draggedAppKey != nil && appKey == hoverTargetAppKey && appKey != draggedAppKey
    }

    private func appGroupLayout(columnWidth: CGFloat) -> AppGroupLayout {
        let keys = appGroups.map(\.id)
        let step = columnWidth + 6
        let minXs = keys.indices.map { CGFloat($0) * step }
        let maxXs = minXs.map { $0 + columnWidth }
        return AppGroupLayout(keys: keys, minXs: minXs, maxXs: maxXs)
    }

    private func taskbarAppGroupLayout(itemWidth: CGFloat) -> AppGroupLayout {
        let step = itemWidth + 4
        var keys: [String] = []
        var minXs: [CGFloat] = []
        var maxXs: [CGFloat] = []
        var index = 0

        while index < orderedWindows.count {
            let key = orderedWindows[index].appKey
            let start = index
            while index + 1 < orderedWindows.count, orderedWindows[index + 1].appKey == key {
                index += 1
            }
            keys.append(key)
            minXs.append(CGFloat(start) * step)
            maxXs.append(CGFloat(index) * step + itemWidth)
            index += 1
        }
        return AppGroupLayout(keys: keys, minXs: minXs, maxXs: maxXs)
    }
}

private extension WindowModel {
    var renderStateID: String {
        "\(id)|\(title)|\(isMinimized)|\(isFocused)|\(isMain)"
    }
}

private struct AppWindowGroup: Identifiable {
    let id: String
    let windows: [WindowModel]
}

private enum AppDragDirection: Equatable {
    case left
    case right
}

private struct AppGroupLayout {
    let keys: [String]
    let minXs: [CGFloat]
    let maxXs: [CGFloat]
}

struct WindowTaskItemView: View {
    let window: WindowModel
    let availableWidth: CGFloat
    let appearance: TaskbarAppearance
    let onShowAppWindows: () -> Void
    let onClose: () -> Void
    @State private var isHovered = false
    @State private var showingLongPressMenu = false

    var body: some View {
        HStack(alignment: .center, spacing: availableWidth < 72 ? 0 : 7) {
            Image(nsImage: window.applicationIcon ?? fallbackIcon)
                .resizable()
                .frame(width: iconSize, height: iconSize)
            if availableWidth >= 72 {
                VStack(alignment: .leading, spacing: 0) {
                    Text(window.title)
                        .font(.system(size: 11.5, weight: window.isFocused ? .semibold : .medium))
                        .foregroundStyle(titleColor)
                        .lineLimit(1)
                    if availableWidth >= 132 {
                        Text(window.applicationName)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(subtitleColor)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if window.isMinimized && availableWidth >= 116 {
                Image(systemName: "minus.circle")
                    .font(.caption2)
                    .foregroundStyle(subtitleColor)
                    .help("此窗口已最小化")
            }
        }
        .padding(.horizontal, availableWidth < 72 ? 3 : 9)
        .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34, alignment: availableWidth < 72 ? .center : .leading)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 7)
                    .fill(cardSurfaceColor)
                RoundedRectangle(cornerRadius: 7)
                    .fill(itemBaseBackground)
            }
        }
        .overlay(alignment: .bottom) {
            if window.isFocused {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(height: 3)
                    .padding(.horizontal, 9)
                    .padding(.bottom, 1)
            }
        }
        .scaleEffect(isHovered ? 1.012 : 1.0)
        .shadow(color: isHovered ? Color.black.opacity(appearance == .dark ? 0.28 : 0.12) : .clear, radius: 4, y: 1)
        .zIndex(isHovered ? 2 : (window.isFocused ? 1 : 0))
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .onHover { isHovered = $0 }
        .help("点击显示窗口；再次点击当前焦点窗口会最小化；拖动可调整 App 顺序")
        .onLongPressGesture(minimumDuration: 0.5) { showingLongPressMenu = true }
        .popover(isPresented: $showingLongPressMenu, arrowEdge: .bottom) {
            WindowActionMenu(onShowAppWindows: { showingLongPressMenu = false; onShowAppWindows() }, onClose: { showingLongPressMenu = false; onClose() })
        }
    }

    private var fallbackIcon: NSImage {
        NSImage(named: NSImage.applicationIconName) ?? NSImage(size: NSSize(width: 24, height: 24))
    }

    private var itemBaseBackground: Color {
        if window.isFocused {
            return appearance == .dark ? Color.white.opacity(0.44) : Color.white.opacity(0.66)
        }
        if isHovered {
            return appearance == .dark ? Color.white.opacity(0.11) : Color.black.opacity(0.07)
        }
        return appearance == .dark ? Color.white.opacity(0.055) : Color.black.opacity(0.025)
    }

    private var cardSurfaceColor: Color {
        appearance == .dark ? Color.black.opacity(0.08) : Color.white.opacity(0.82)
    }

    private var titleColor: Color {
        return appearance == .dark ? Color.white.opacity(0.96) : Color.black.opacity(0.88)
    }

    private var subtitleColor: Color {
        return appearance == .dark ? Color.white.opacity(0.62) : Color.black.opacity(0.56)
    }

    private var iconSize: CGFloat {
        availableWidth < 48 ? 18 : 20
    }
}

private struct TaskbarControlButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
                .background(
                    Color.primary.opacity(isHovered ? 0.09 : 0),
                    in: RoundedRectangle(cornerRadius: 7)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .help(help)
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
