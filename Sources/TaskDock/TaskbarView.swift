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
    let onOpenFavorite: (FavoriteApp) -> Void
    let showsFavorites: Bool
    let showsControls: Bool
    let showsEmptyState: Bool
    @ObservedObject var settings: SettingsStore
    let onSettingsChanged: () -> Void
    let onAppDragChanged: (Bool) -> Void
    let onFavoriteMagnificationChanged: (CGFloat) -> Void
    let onPanelDragChanged: (CGSize) -> Void
    let onPanelDragEnded: () -> Void
    @State private var draggedAppKey: String?
    @State private var dragTranslation: CGFloat = 0
    @State private var dragStartAppKeys: [String]?
    @State private var hoverTargetAppKey: String?
    @State private var dragDirection: AppDragDirection?
    @State private var isOptionMovingPanel = false
    @State private var favoriteMagnificationExpansion: CGFloat = 0

    var body: some View {
        Group {
            switch settings.layoutMode {
            case .taskbar, .dockCompanion:
                taskbarView
            case .matrix:
                matrixView
            }
        }
        .preferredColorScheme(settings.layoutMode == .dockCompanion ? nil : settings.appearance.colorScheme)
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
                                            isDockCompanion: false,
                                            onShowAppWindows: { onShowAppWindows(window) },
                                            onClose: { onClose(window) },
                                            onToggleFavorite: { toggleFavorite(window) },
                                            favoriteActionTitle: favoriteMenuTitle(for: window)
                                        )
                                        .id(window.renderStateID)
                                        .frame(width: columnWidth, height: 32)
                                        .contentShape(Rectangle())
                                        .onTapGesture { onSelect(window) }
                                        .simultaneousGesture(appReorderGesture(for: window, columnWidth: columnWidth))
                                        .contextMenu {
                                            Button(favoriteMenuTitle(for: window)) { toggleFavorite(window) }
                                            Divider()
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
                } else {
                    if showsFavorites && !settings.favoriteApps.isEmpty {
                        FavoriteDockView(
                            favorites: settings.favoriteApps,
                            onOpen: onOpenFavorite,
                            onRemove: { favorite in
                                settings.removeFavorite(favorite)
                                onSettingsChanged()
                            },
                            onMagnificationExpansionChanged: { expansion in
                                withAnimation(.easeOut(duration: 0.16)) {
                                    favoriteMagnificationExpansion = expansion
                                }
                                onFavoriteMagnificationChanged(expansion)
                            }
                        )
                        .padding(.leading, 6)

                        Divider()
                            .frame(height: 22)
                    }

                    if windows.isEmpty && showsEmptyState {
                        Text("没有可显示的窗口")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                        taskbarDragArea
                    } else if !windows.isEmpty {
                        let itemWidth = taskbarItemWidth(for: geometry.size.width)
                        HStack(spacing: 4) {
                            ForEach(orderedWindows) { window in
                                WindowTaskItemView(
                                    window: window,
                                    availableWidth: itemWidth,
                                    appearance: effectiveAppearance,
                                    isDockCompanion: settings.layoutMode == .dockCompanion,
                                    onShowAppWindows: { onShowAppWindows(window) },
                                    onClose: { onClose(window) },
                                    onToggleFavorite: { toggleFavorite(window) },
                                    favoriteActionTitle: favoriteMenuTitle(for: window)
                                )
                                .id(window.renderStateID)
                                .frame(width: itemWidth, height: 31)
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
                                    Button(favoriteMenuTitle(for: window)) { toggleFavorite(window) }
                                    Divider()
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
                        .padding(.leading, showsFavorites && !settings.favoriteApps.isEmpty ? 0 : 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                }

                if showsControls {
                    TaskbarControlButton(systemImage: "minus.rectangle", help: "最小化全部窗口", action: onMinimizeAll)
                    .padding(.horizontal, 8)
                }
            }
            .frame(height: taskbarBaseHeight)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .background(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 10)
                .fill(settings.layoutMode == .dockCompanion ? .regularMaterial : .ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 10).fill(taskbarSurfaceColor))
                .frame(height: taskbarBaseHeight)
        }
        .overlay(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 10)
                .stroke(taskbarBorderColor)
                .frame(height: taskbarBaseHeight)
        }
        .shadow(
            color: settings.layoutMode == .dockCompanion ? Color.black.opacity(0.16) : .clear,
            radius: 9,
            y: 4
        )
        .padding(2)
    }

    private func taskbarItemWidth(for totalWidth: CGFloat) -> CGFloat {
        guard !windows.isEmpty else { return 0 }
        let controlsAndPadding: CGFloat = showsControls ? 48 : 16
        let favoriteWidth = !showsFavorites || settings.favoriteApps.isEmpty
            ? 0
            : CGFloat(settings.favoriteApps.count) * 32 + CGFloat(max(settings.favoriteApps.count - 1, 0)) * 2 + 14 + favoriteMagnificationExpansion
        let totalSpacing = CGFloat(max(windows.count - 1, 0)) * 4
        let available = max(totalWidth - controlsAndPadding - favoriteWidth - totalSpacing, 0)
        return min(216, max(27, available / CGFloat(windows.count)))
    }

    private var taskbarSurfaceColor: Color {
        if settings.layoutMode == .dockCompanion {
            return .clear
        }
        return settings.appearance == .dark ? Color.black.opacity(0.28) : Color.white.opacity(0.64)
    }

    private var taskbarBorderColor: Color {
        if settings.layoutMode == .dockCompanion {
            return Color.white.opacity(0.2)
        }
        return settings.appearance == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.12)
    }

    private var taskbarBaseHeight: CGFloat {
        settings.layoutMode == .dockCompanion ? settings.dockCompanionHeight : 38
    }

    private var effectiveAppearance: TaskbarAppearance {
        guard settings.layoutMode == .dockCompanion else { return settings.appearance }
        return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
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
        let controlAndSpacing: CGFloat = 44 + CGFloat(max(count - 1, 0)) * 6
        return min(162, max(83, (totalWidth - controlAndSpacing) / CGFloat(count)))
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
        TaskbarControlButton(systemImage: "minus.rectangle", help: "最小化全部窗口", action: onMinimizeAll)
        .padding(3)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    private func favoriteMenuTitle(for window: WindowModel) -> String {
        settings.isFavorite(window.appKey) ? "取消收藏" : "固定到收藏"
    }

    private func toggleFavorite(_ window: WindowModel) {
        settings.toggleFavorite(for: window)
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
    let isDockCompanion: Bool
    let onShowAppWindows: () -> Void
    let onClose: () -> Void
    let onToggleFavorite: () -> Void
    let favoriteActionTitle: String
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
        .padding(.horizontal, availableWidth < 72 ? 3 : 8)
        .frame(maxWidth: .infinity, minHeight: 31, maxHeight: 31, alignment: availableWidth < 72 ? .center : .leading)
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
            WindowActionMenu(
                favoriteActionTitle: favoriteActionTitle,
                onToggleFavorite: { showingLongPressMenu = false; onToggleFavorite() },
                onShowAppWindows: { showingLongPressMenu = false; onShowAppWindows() },
                onClose: { showingLongPressMenu = false; onClose() }
            )
        }
    }

    private var fallbackIcon: NSImage {
        NSImage(named: NSImage.applicationIconName) ?? NSImage(size: NSSize(width: 24, height: 24))
    }

    private var itemBaseBackground: Color {
        if window.isFocused {
            if isDockCompanion && window.bundleIdentifier == "com.apple.finder" {
                return appearance == .dark ? Color.white.opacity(0.28) : Color.white.opacity(0.38)
            }
            return appearance == .dark ? Color.white.opacity(0.44) : Color.white.opacity(0.66)
        }
        if isHovered {
            return appearance == .dark ? Color.white.opacity(0.11) : Color.black.opacity(0.07)
        }
        return appearance == .dark ? Color.white.opacity(0.055) : Color.black.opacity(0.025)
    }

    private var cardSurfaceColor: Color {
        if isDockCompanion && window.bundleIdentifier == "com.apple.finder" {
            return appearance == .dark ? Color.black.opacity(0.06) : Color.white.opacity(0.64)
        }
        return appearance == .dark ? Color.black.opacity(0.08) : Color.white.opacity(0.82)
    }

    private var titleColor: Color {
        return appearance == .dark ? Color.white.opacity(0.96) : Color.black.opacity(0.88)
    }

    private var subtitleColor: Color {
        return appearance == .dark ? Color.white.opacity(0.62) : Color.black.opacity(0.56)
    }

    private var iconSize: CGFloat {
        availableWidth < 48 ? 16 : 18
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

private struct FavoriteDockView: View {
    let favorites: [FavoriteApp]
    let onOpen: (FavoriteApp) -> Void
    let onRemove: (FavoriteApp) -> Void
    let onMagnificationExpansionChanged: (CGFloat) -> Void
    @State private var pointerX: CGFloat?

    private let itemStep: CGFloat = 32
    private let buttonSize: CGFloat = 30
    private let magnificationExpansion: CGFloat = 30

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            FavoriteHoverTrackingView { location in
                let wasInside = pointerX != nil
                let isInside = location != nil
                pointerX = location
                if wasInside != isInside {
                    onMagnificationExpansionChanged(isInside ? magnificationExpansion : 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            ForEach(Array(favorites.enumerated()), id: \.element.id) { index, favorite in
                FavoriteAppButton(
                    favorite: favorite,
                    magnification: magnification(for: index),
                    horizontalOffset: horizontalOffset(for: index),
                    isHovered: isHovered(index: index),
                    onOpen: { onOpen(favorite) },
                    onRemove: { onRemove(favorite) }
                )
                .offset(x: CGFloat(index) * itemStep + currentMagnificationExpansion / 2)
            }
        }
        .frame(
            width: CGFloat(favorites.count) * itemStep + currentMagnificationExpansion,
            height: 30,
            alignment: .bottomLeading
        )
        .animation(.easeOut(duration: 0.16), value: pointerX != nil)
        .onDisappear {
            pointerX = nil
            onMagnificationExpansionChanged(0)
        }
    }

    private var currentMagnificationExpansion: CGFloat {
        pointerX == nil ? 0 : magnificationExpansion
    }

    private func iconCenter(for index: Int) -> CGFloat {
        currentMagnificationExpansion / 2 + CGFloat(index) * itemStep + buttonSize / 2
    }

    private func magnification(for index: Int) -> CGFloat {
        guard let pointerX else { return 1 }
        let distance = abs(pointerX - iconCenter(for: index))
        let normalizedDistance = distance / 34
        return 1 + 0.5 * exp(-(normalizedDistance * normalizedDistance))
    }

    private func horizontalOffset(for index: Int) -> CGFloat {
        guard let pointerX else { return 0 }
        let delta = iconCenter(for: index) - pointerX
        guard abs(delta) > 1 else { return 0 }
        let normalizedDistance = abs(delta) / 48
        let displacement = 8 * exp(-(normalizedDistance * normalizedDistance))
        return delta < 0 ? -displacement : displacement
    }

    private func isHovered(index: Int) -> Bool {
        guard let pointerX else { return false }
        return abs(pointerX - iconCenter(for: index)) <= itemStep / 2
    }
}

private struct FavoriteAppButton: View {
    let favorite: FavoriteApp
    let magnification: CGFloat
    let horizontalOffset: CGFloat
    let isHovered: Bool
    let onOpen: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Button(action: onOpen) {
            Image(nsImage: applicationIcon)
                .resizable()
                .frame(width: 26, height: 26)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .scaleEffect(magnification, anchor: .bottom)
        .offset(x: horizontalOffset)
        .zIndex(isHovered ? 10 : magnification)
        .shadow(color: Color.black.opacity(isHovered ? 0.26 : 0), radius: 5, y: 2)
        .help("打开 \(favorite.applicationName)")
        .contextMenu {
            Button("取消收藏", role: .destructive, action: onRemove)
        }
        .accessibilityLabel("收藏：\(favorite.applicationName)")
        .accessibilityHint("点击打开 App")
    }

    private var applicationIcon: NSImage {
        let workspace = NSWorkspace.shared
        if let bundleIdentifier = favorite.bundleIdentifier,
           let url = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return workspace.icon(forFile: url.path)
        }
        if let bundlePath = favorite.bundlePath {
            return workspace.icon(forFile: bundlePath)
        }
        return NSImage(named: NSImage.applicationIconName) ?? NSImage(size: NSSize(width: 24, height: 24))
    }
}

private struct FavoriteHoverTrackingView: NSViewRepresentable {
    let onLocationChanged: (CGFloat?) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onLocationChanged = onLocationChanged
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onLocationChanged = onLocationChanged
    }

    final class TrackingView: NSView {
        var onLocationChanged: ((CGFloat?) -> Void)?
        private var trackingAreaReference: NSTrackingArea?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.acceptsMouseMovedEvents = true
        }

        override func updateTrackingAreas() {
            if let trackingAreaReference {
                removeTrackingArea(trackingAreaReference)
            }
            let trackingArea = NSTrackingArea(
                rect: bounds,
                options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(trackingArea)
            trackingAreaReference = trackingArea
            super.updateTrackingAreas()
        }

        override func mouseEntered(with event: NSEvent) {
            reportLocation(event)
        }

        override func mouseMoved(with event: NSEvent) {
            reportLocation(event)
        }

        override func mouseExited(with event: NSEvent) {
            onLocationChanged?(nil)
        }

        private func reportLocation(_ event: NSEvent) {
            onLocationChanged?(convert(event.locationInWindow, from: nil).x)
        }
    }
}

private struct WindowActionMenu: View {
    let favoriteActionTitle: String
    let onToggleFavorite: () -> Void
    let onShowAppWindows: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(favoriteActionTitle, action: onToggleFavorite)
            Divider()
            Button("显示该 App 的所有窗口", action: onShowAppWindows)
            Divider()
            Button("关闭此窗口", role: .destructive, action: onClose)
        }
        .padding(10)
    }
}
