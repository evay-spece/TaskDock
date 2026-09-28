import AppKit
import SwiftUI

struct TaskbarView: View {
    let windows: [WindowModel]
    let isAccessibilityTrusted: Bool
    let onRequestPermission: () -> Void
    let onSelect: (WindowModel) -> Void
    let onMinimizeAll: () -> Void
    let onShowAppWindows: (WindowModel) -> Void
    let onBlockWindowType: (WindowModel) -> Void
    let onClose: (WindowModel) -> Void
    let onOpenFavorite: (FavoriteApp) -> Void
    let showsFavorites: Bool
    let showsControls: Bool
    let showsEmptyState: Bool
    @ObservedObject var settings: SettingsStore
    let onSettingsChanged: () -> Void
    let onAppDragChanged: (Bool) -> Void
    let onPanelDragChanged: (CGSize) -> Void
    let onPanelDragEnded: () -> Void
    @State private var draggedAppKey: String?
    @State private var dragTranslation: CGFloat = 0
    @State private var dragStartAppKeys: [String]?
    @State private var dragStartGroupLayout: AppGroupLayout?
    @State private var hoverTargetAppKey: String?
    @State private var dragDirection: AppDragDirection?
    @State private var pendingDropCandidate: PendingDropCandidate?
    @State private var pendingDropToken: UUID?
    @State private var isSettlingAppDrag = false
    @State private var isOptionMovingPanel = false

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
                                            showApplicationName: settings.showApplicationName,
                                            highlightStyle: settings.taskItemHighlightStyle,
                                            nonSelectedItemTransparency: settings.nonSelectedItemTransparency,
                                            onShowAppWindows: { onShowAppWindows(window) },
                                            onBlockWindowType: { onBlockWindowType(window) },
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
                                            Button("屏蔽此类窗口") { onBlockWindowType(window) }
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
                                .offset(x: appColumnOffset(for: group.id))
                                .animation(draggedAppKey == group.id ? nil : appReorderAnimation, value: hoverTargetAppKey)
                                .animation(draggedAppKey == group.id ? nil : appReorderAnimation, value: dragDirection)
                                .opacity(draggedAppKey == group.id ? 0.88 : 1)
                                .scaleEffect(isDropTarget(group.id) ? 0.98 : 1)
                                .overlay {
                                    if isReorderHighlighted(group.id) {
                                        RoundedRectangle(cornerRadius: 9)
                                            .fill(Color.accentColor.opacity(reorderHighlightOpacity(for: group.id)))
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 9)
                                                    .stroke(Color.accentColor.opacity(0.72), lineWidth: 1.5)
                                            }
                                            .allowsHitTesting(false)
                                    }
                                }
                                .shadow(color: isDropTarget(group.id) ? Color.accentColor.opacity(0.2) : .clear, radius: 5)
                                .zIndex(draggedAppKey == group.id ? 20 : 0)
                                .transaction { transaction in
                                    if draggedAppKey == group.id && !isSettlingAppDrag {
                                        transaction.animation = nil
                                        transaction.disablesAnimations = true
                                    }
                                }
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
                            hoverFeedbackEnabled: settings.favoriteMagnificationEnabled,
                            onOpen: onOpenFavorite,
                            onRemove: { favorite in
                                settings.removeFavorite(favorite)
                                onSettingsChanged()
                            },
                            onReorder: { settings.reorderFavorites($0) },
                            onDragChanged: onAppDragChanged
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
                        HStack(spacing: taskbarItemSpacing) {
                            ForEach(appGroups) { group in
                                HStack(spacing: taskbarItemSpacing) {
                                    ForEach(group.windows) { window in
                                        WindowTaskItemView(
                                            window: window,
                                            availableWidth: itemWidth,
                                            appearance: effectiveAppearance,
                                            isDockCompanion: settings.layoutMode == .dockCompanion,
                                            isTaskbarMode: settings.layoutMode == .taskbar,
                                            showApplicationName: settings.showApplicationName,
                                            highlightStyle: settings.taskItemHighlightStyle,
                                            nonSelectedItemTransparency: settings.nonSelectedItemTransparency,
                                            itemHeight: taskbarItemHeight,
                                            contentScale: taskbarContentScale,
                                            onShowAppWindows: { onShowAppWindows(window) },
                                            onBlockWindowType: { onBlockWindowType(window) },
                                            onClose: { onClose(window) },
                                            onToggleFavorite: { toggleFavorite(window) },
                                            favoriteActionTitle: favoriteMenuTitle(for: window)
                                        )
                                        .id(window.renderStateID)
                                        .frame(width: itemWidth, height: taskbarItemHeight)
                                        .contentShape(Rectangle())
                                        .onTapGesture { onSelect(window) }
                                        .simultaneousGesture(taskbarReorderGesture(for: window, itemWidth: itemWidth))
                                        .contextMenu {
                                            Button(favoriteMenuTitle(for: window)) { toggleFavorite(window) }
                                            Divider()
                                            Button("显示该 App 的所有窗口") { onShowAppWindows(window) }
                                            Divider()
                                            Button("屏蔽此类窗口") { onBlockWindowType(window) }
                                            Divider()
                                            Button("关闭此窗口", role: .destructive) { onClose(window) }
                                        }
                                        .accessibilityElement(children: .combine)
                                        .accessibilityAddTraits(.isButton)
                                        .accessibilityValue(window.isFocused ? "当前焦点窗口" : "非焦点窗口")
                                        .accessibilityAction { onSelect(window) }
                                    }
                                }
                                .offset(x: taskbarItemOffset(for: group.id))
                                .animation(draggedAppKey == group.id ? nil : appReorderAnimation, value: hoverTargetAppKey)
                                .animation(draggedAppKey == group.id ? nil : appReorderAnimation, value: dragDirection)
                                .opacity(draggedAppKey == group.id ? 0.88 : 1)
                                .scaleEffect(isDropTarget(group.id) ? 0.98 : 1)
                                .overlay {
                                    if isReorderHighlighted(group.id) {
                                        RoundedRectangle(cornerRadius: 7 * taskbarContentScale)
                                            .fill(Color.accentColor.opacity(reorderHighlightOpacity(for: group.id)))
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 7 * taskbarContentScale)
                                                    .stroke(Color.accentColor.opacity(0.72), lineWidth: 1.5)
                                            }
                                            .allowsHitTesting(false)
                                    }
                                }
                                .zIndex(draggedAppKey == group.id ? 20 : 0)
                                .transaction { transaction in
                                    if draggedAppKey == group.id && !isSettlingAppDrag {
                                        transaction.animation = nil
                                        transaction.disablesAnimations = true
                                    }
                                }
                            }
                        }
                        .padding(.leading, showsFavorites && !settings.favoriteApps.isEmpty
                            ? 0
                            : (settings.layoutMode == .dockCompanion ? 2 : 8) * taskbarPanelScale)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                }

                if showsControls && (settings.layoutMode != .dockCompanion || settings.dockCompanionShowsBottomBar) {
                    TaskbarControlButton(
                        systemImage: "minus.rectangle",
                        help: "最小化全部窗口",
                        scale: taskbarContentScale,
                        isTaskbarMode: settings.layoutMode == .taskbar,
                        action: onMinimizeAll
                    )
                    .padding(.horizontal, 8 * taskbarPanelScale)
                }
            }
            .frame(height: taskbarBaseHeight)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .background(alignment: .bottom) {
            if settings.layoutMode != .dockCompanion || settings.dockCompanionShowsBottomBar {
                RoundedRectangle(cornerRadius: 10 * min(taskbarContentScale, 1.3))
                    .fill(settings.layoutMode == .dockCompanion ? .regularMaterial : .ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 10 * min(taskbarContentScale, 1.3)).fill(taskbarSurfaceColor))
                    .frame(height: taskbarBaseHeight)
            }
        }
        .overlay(alignment: .bottom) {
            if settings.layoutMode != .dockCompanion || settings.dockCompanionShowsBottomBar {
                RoundedRectangle(cornerRadius: 10 * min(taskbarContentScale, 1.3))
                    .stroke(taskbarBorderColor)
                    .frame(height: taskbarBaseHeight)
            }
        }
        .shadow(
            color: settings.layoutMode == .dockCompanion && settings.dockCompanionShowsBottomBar ? Color.black.opacity(0.16) : .clear,
            radius: 9,
            y: 4
        )
        .padding(2)
    }

    private func taskbarItemWidth(for totalWidth: CGFloat) -> CGFloat {
        guard !windows.isEmpty else { return 0 }
        let controlsAndPadding: CGFloat
        if settings.layoutMode == .dockCompanion {
            if !showsControls {
                controlsAndPadding = 0
            } else {
                controlsAndPadding = (settings.dockCompanionShowsBottomBar ? 48 : 8) * taskbarPanelScale
            }
        } else {
            controlsAndPadding = (showsControls ? 48 : 16) * taskbarPanelScale
        }
        let favoriteWidth = !showsFavorites || settings.favoriteApps.isEmpty
            ? 0
            : CGFloat(settings.favoriteApps.count) * 32 + CGFloat(max(settings.favoriteApps.count - 1, 0)) * 2 + 14
        let totalSpacing = CGFloat(max(windows.count - 1, 0)) * taskbarItemSpacing
        let available = max(totalWidth - controlsAndPadding - favoriteWidth - totalSpacing, 0)
        let maximumWidth = settings.layoutMode == .dockCompanion
            ? DockCompanionSizing.maximumItemWidth(for: settings.dockCompanionHeight)
            : 216
        let minimumWidth = settings.layoutMode == .dockCompanion
            ? DockCompanionSizing.minimumItemWidth(for: settings.dockCompanionHeight)
            : 27
        return min(maximumWidth, max(minimumWidth, available / CGFloat(windows.count)))
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

    private var taskbarPanelScale: CGFloat {
        settings.layoutMode == .dockCompanion
            ? DockCompanionSizing.scale(for: settings.dockCompanionHeight)
            : 1
    }

    private var taskbarContentScale: CGFloat {
        settings.layoutMode == .dockCompanion
            ? DockCompanionSizing.contentScale(for: settings.dockCompanionHeight)
            : 1
    }

    private var taskbarItemHeight: CGFloat {
        guard settings.layoutMode == .dockCompanion else { return 31 }
        return settings.dockCompanionShowsBottomBar
            ? DockCompanionSizing.itemHeight(for: settings.dockCompanionHeight)
            : settings.dockCompanionHeight
    }

    private var taskbarItemSpacing: CGFloat {
        settings.layoutMode == .dockCompanion
            ? DockCompanionSizing.itemSpacing(for: settings.dockCompanionHeight)
            : 4
    }

    private var appReorderAnimation: Animation {
        settings.layoutMode == .taskbar
            ? .spring(response: 0.30, dampingFraction: 0.86)
            : .easeOut(duration: 0.16)
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
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { value in
                guard !isSettlingAppDrag, !NSEvent.modifierFlags.contains(.option) else { return }
                if draggedAppKey == nil {
                    let groups = appGroupLayout(columnWidth: columnWidth)
                    guard groups.keys.contains(window.appKey) else { return }
                    draggedAppKey = window.appKey
                    dragStartAppKeys = groups.keys
                    dragStartGroupLayout = groups
                    onAppDragChanged(true)
                }

                guard draggedAppKey == window.appKey else { return }

                dragTranslation = value.translation.width
                if let dragStartGroupLayout {
                    updateDropTarget(in: dragStartGroupLayout)
                }
            }
            .onEnded { _ in
                guard draggedAppKey == window.appKey else { return }
                finishAppReorder(in: dragStartGroupLayout ?? appGroupLayout(columnWidth: columnWidth), spacing: 6)
            }
    }

    private func taskbarReorderGesture(for window: WindowModel, itemWidth: CGFloat) -> some Gesture {
        // A slightly larger threshold keeps normal clicks with small hand motion
        // from being interpreted as app-reordering drags.
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { value in
                guard !isSettlingAppDrag, !NSEvent.modifierFlags.contains(.option) else { return }
                if draggedAppKey == nil {
                    let groups = taskbarAppGroupLayout(itemWidth: itemWidth)
                    guard groups.keys.contains(window.appKey) else { return }
                    draggedAppKey = window.appKey
                    dragStartAppKeys = groups.keys
                    dragStartGroupLayout = groups
                    onAppDragChanged(true)
                }

                guard draggedAppKey == window.appKey else { return }
                dragTranslation = value.translation.width
                if let dragStartGroupLayout {
                    updateDropTarget(in: dragStartGroupLayout)
                }
            }
            .onEnded { _ in
                guard draggedAppKey == window.appKey else { return }
                finishAppReorder(in: dragStartGroupLayout ?? taskbarAppGroupLayout(itemWidth: itemWidth), spacing: taskbarItemSpacing)
            }
    }

    private func finishAppReorder(in groups: AppGroupLayout, spacing: CGFloat) {
        isSettlingAppDrag = true
        pendingDropCandidate = nil
        pendingDropToken = nil
        var positionChange: CGFloat = 0
        if let sourceKey = draggedAppKey,
           let targetKey = hoverTargetAppKey,
           let direction = dragDirection,
           var keys = dragStartAppKeys,
           let sourceIndex = keys.firstIndex(of: sourceKey) {
            keys.remove(at: sourceIndex)
            if let targetIndex = keys.firstIndex(of: targetKey) {
                let insertionIndex = direction == .left ? targetIndex : targetIndex + 1
                keys.insert(sourceKey, at: min(insertionIndex, keys.count))
                if let oldIndex = groups.keys.firstIndex(of: sourceKey),
                   let newIndex = keys.firstIndex(of: sourceKey) {
                    let widths = Dictionary(uniqueKeysWithValues: groups.keys.indices.map {
                        (groups.keys[$0], groups.maxXs[$0] - groups.minXs[$0])
                    })
                    let newMinX = keys.prefix(newIndex).reduce(CGFloat.zero) {
                        $0 + (widths[$1] ?? 0) + spacing
                    }
                    positionChange = newMinX - groups.minXs[oldIndex]
                }
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    dragTranslation -= positionChange
                    hoverTargetAppKey = nil
                    dragDirection = nil
                    settings.applyVisibleAppOrder(keys)
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            withAnimation(.easeOut(duration: 0.18)) {
                dragTranslation = 0
                hoverTargetAppKey = nil
                dragDirection = nil
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            draggedAppKey = nil
            dragStartAppKeys = nil
            dragStartGroupLayout = nil
            isSettlingAppDrag = false
            onAppDragChanged(false)
        }
    }

    private func updateDropTarget(in groups: AppGroupLayout) {
        guard let sourceKey = draggedAppKey,
              let sourceIndex = groups.keys.firstIndex(of: sourceKey),
              dragTranslation != 0 else {
            pendingDropCandidate = nil
            pendingDropToken = nil
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
                    return draggedLeadingEdge <= groups.minXs[$0] + width * 0.50
                }
                .min()
        } else {
            let draggedTrailingEdge = groups.maxXs[sourceIndex] + dragTranslation
            targetIndex = groups.keys.indices
                .filter { $0 > sourceIndex }
                .filter {
                    let width = groups.maxXs[$0] - groups.minXs[$0]
                    return draggedTrailingEdge >= groups.maxXs[$0] - width * 0.50
                }
                .max()
        }

        guard let targetIndex else {
            pendingDropCandidate = nil
            pendingDropToken = nil
            hoverTargetAppKey = nil
            dragDirection = nil
            return
        }

        let candidate = PendingDropCandidate(appKey: groups.keys[targetIndex], direction: direction)
        if hoverTargetAppKey == candidate.appKey && dragDirection == candidate.direction { return }
        if pendingDropCandidate == candidate { return }

        hoverTargetAppKey = nil
        dragDirection = nil
        pendingDropCandidate = candidate
        let token = UUID()
        pendingDropToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard pendingDropToken == token,
                  pendingDropCandidate == candidate,
                  draggedAppKey == sourceKey,
                  !isSettlingAppDrag else { return }
            hoverTargetAppKey = candidate.appKey
            dragDirection = candidate.direction
            pendingDropCandidate = nil
            pendingDropToken = nil
        }
    }

    private func appColumnOffset(for appKey: String) -> CGFloat {
        reorderOffset(for: appKey, spacing: 6)
    }

    private func taskbarItemOffset(for appKey: String) -> CGFloat {
        reorderOffset(for: appKey, spacing: taskbarItemSpacing)
    }

    private func reorderOffset(for appKey: String, spacing: CGFloat) -> CGFloat {
        if appKey == draggedAppKey { return dragTranslation }
        guard let draggedAppKey,
              let hoverTargetAppKey,
              let layout = dragStartGroupLayout,
              let sourceIndex = layout.keys.firstIndex(of: draggedAppKey),
              let targetIndex = layout.keys.firstIndex(of: hoverTargetAppKey),
              let itemIndex = layout.keys.firstIndex(of: appKey) else { return 0 }

        let draggedWidth = layout.maxXs[sourceIndex] - layout.minXs[sourceIndex]
        let displacement = draggedWidth + spacing
        if sourceIndex < targetIndex, (sourceIndex + 1...targetIndex).contains(itemIndex) {
            return -displacement
        }
        if targetIndex < sourceIndex, (targetIndex..<sourceIndex).contains(itemIndex) {
            return displacement
        }
        return 0
    }

    private func isDropTarget(_ appKey: String) -> Bool {
        draggedAppKey != nil && appKey == hoverTargetAppKey && appKey != draggedAppKey
    }

    private func isReorderHighlighted(_ appKey: String) -> Bool {
        draggedAppKey == appKey || isDropTarget(appKey)
    }

    private func reorderHighlightOpacity(for appKey: String) -> Double {
        if draggedAppKey == appKey { return 0.16 }
        if isDropTarget(appKey) { return 0.12 }
        return 0
    }

    private func appGroupLayout(columnWidth: CGFloat) -> AppGroupLayout {
        let keys = appGroups.map(\.id)
        let step = columnWidth + 6
        let minXs = keys.indices.map { CGFloat($0) * step }
        let maxXs = minXs.map { $0 + columnWidth }
        return AppGroupLayout(keys: keys, minXs: minXs, maxXs: maxXs)
    }

    private func taskbarAppGroupLayout(itemWidth: CGFloat) -> AppGroupLayout {
        let step = itemWidth + taskbarItemSpacing
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

private struct PendingDropCandidate: Equatable {
    let appKey: String
    let direction: AppDragDirection
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
    var isTaskbarMode: Bool = false
    var showApplicationName: Bool = true
    var highlightStyle: TaskItemHighlightStyle = .white
    var nonSelectedItemTransparency: Double = 0
    var itemHeight: CGFloat = 31
    var contentScale: CGFloat = 1
    let onShowAppWindows: () -> Void
    let onBlockWindowType: () -> Void
    let onClose: () -> Void
    let onToggleFavorite: () -> Void
    let favoriteActionTitle: String
    @State private var isHovered = false
    @State private var showingLongPressMenu = false

    var body: some View {
        HStack(alignment: .center, spacing: availableWidth < textVisibilityWidth ? 0 : 7 * contentScale) {
            Image(nsImage: window.applicationIcon ?? fallbackIcon)
                .resizable()
                .frame(width: iconSize, height: iconSize)
            if availableWidth >= textVisibilityWidth {
                VStack(alignment: .leading, spacing: 0) {
                    Text(window.title)
                        .font(.system(size: (showApplicationName ? 11.5 : 10.5) * contentScale, weight: .medium))
                        .foregroundStyle(titleColor)
                        .lineLimit(showApplicationName ? 1 : 2)
                        .fixedSize(horizontal: false, vertical: !showApplicationName)
                    if showApplicationName && availableWidth >= subtitleVisibilityWidth {
                        Text(window.applicationName)
                            .font(.system(size: 9.5 * contentScale, weight: .medium))
                            .foregroundStyle(subtitleColor)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if window.isMinimized && availableWidth >= minimizedIndicatorWidth {
                Image(systemName: "minus.circle")
                    .font(.system(size: 9.5 * contentScale))
                    .foregroundStyle(subtitleColor)
                    .help("此窗口已最小化")
            }
        }
        .padding(.horizontal, availableWidth < textVisibilityWidth ? 3 * contentScale : 8 * contentScale)
        .frame(maxWidth: .infinity, minHeight: itemHeight, maxHeight: itemHeight, alignment: availableWidth < textVisibilityWidth ? .center : .leading)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 7 * contentScale)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 7 * contentScale)
                    .fill(cardSurfaceColor)
                RoundedRectangle(cornerRadius: 7 * contentScale)
                    .fill(itemBaseBackground)
            }
        }
        .overlay(alignment: .bottom) {
            if window.isFocused {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(height: 3 * contentScale)
                    .padding(.horizontal, 9 * contentScale)
                    .padding(.bottom, contentScale)
            }
        }
        .scaleEffect(isHovered ? 1.012 : 1.0)
        .opacity(window.isFocused ? 1 : 1 - nonSelectedItemTransparency)
        .shadow(color: isHovered ? Color.black.opacity(appearance == .dark ? 0.28 : 0.12) : .clear, radius: 4, y: 1)
        .zIndex(isHovered ? 2 : (window.isFocused ? 1 : 0))
        .animation(
            isTaskbarMode ? .easeInOut(duration: 0.24) : .easeOut(duration: 0.12),
            value: isHovered
        )
        .onHover { isHovered = $0 }
        .help("点击显示窗口；再次点击当前焦点窗口会最小化；拖动可调整 App 顺序")
        .onLongPressGesture(minimumDuration: 0.5) { showingLongPressMenu = true }
        .popover(isPresented: $showingLongPressMenu, arrowEdge: .bottom) {
            WindowActionMenu(
                favoriteActionTitle: favoriteActionTitle,
                onToggleFavorite: { showingLongPressMenu = false; onToggleFavorite() },
                onShowAppWindows: { showingLongPressMenu = false; onShowAppWindows() },
                onBlockWindowType: { showingLongPressMenu = false; onBlockWindowType() },
                onClose: { showingLongPressMenu = false; onClose() }
            )
        }
    }

    private var fallbackIcon: NSImage {
        NSImage(named: NSImage.applicationIconName) ?? NSImage(size: NSSize(width: 24, height: 24))
    }

    private var itemBaseBackground: Color {
        if isHovered || window.isFocused {
            switch highlightStyle {
            case .systemAccent:
                return Color.accentColor.opacity(appearance == .dark ? 0.38 : 0.28)
            case .white:
                if isDockCompanion && window.bundleIdentifier == "com.apple.finder" {
                    return appearance == .dark ? Color.white.opacity(0.28) : Color.white.opacity(0.38)
                }
                return appearance == .dark ? Color.white.opacity(0.44) : Color.white.opacity(0.66)
            }
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
        (availableWidth < 48 * contentScale ? 16 : 18) * contentScale
    }

    private var textVisibilityWidth: CGFloat {
        72 * contentScale
    }

    private var subtitleVisibilityWidth: CGFloat {
        132 * contentScale
    }

    private var minimizedIndicatorWidth: CGFloat {
        116 * contentScale
    }
}

private struct TaskbarControlButton: View {
    let systemImage: String
    let help: String
    var scale: CGFloat = 1
    var isTaskbarMode = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12 * scale, weight: .medium))
                .frame(width: 28 * scale, height: 28 * scale)
                .contentShape(Rectangle())
                .background(
                    Color.primary.opacity(isHovered ? 0.09 : 0),
                    in: RoundedRectangle(cornerRadius: 7 * scale)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(
            isTaskbarMode ? .easeInOut(duration: 0.24) : .easeOut(duration: 0.12),
            value: isHovered
        )
        .help(help)
    }
}

private struct FavoriteDockView: View {
    let favorites: [FavoriteApp]
    let hoverFeedbackEnabled: Bool
    let onOpen: (FavoriteApp) -> Void
    let onRemove: (FavoriteApp) -> Void
    let onReorder: ([String]) -> Void
    let onDragChanged: (Bool) -> Void
    @State private var hoveredFavoriteID: String?
    @State private var isRegionHovered = false
    @State private var draggedFavoriteID: String?
    @State private var dragStartIDs: [String]?
    @State private var dragTranslation: CGFloat = 0
    @State private var hoverTargetID: String?
    @State private var pendingCandidate: PendingDropCandidate?
    @State private var pendingToken: UUID?
    @State private var isSettlingDrag = false

    private let itemStep: CGFloat = 32
    private let buttonSize: CGFloat = 30

    var body: some View {
        HStack(spacing: itemStep - 30) {
            ForEach(favorites) { favorite in
                FavoriteAppButton(
                    favorite: favorite,
                    isHovered: hoverFeedbackEnabled && hoveredFavoriteID == favorite.id,
                    onHoverChange: { isHovered in
                        if isHovered {
                            hoveredFavoriteID = favorite.id
                        } else if hoveredFavoriteID == favorite.id {
                            hoveredFavoriteID = nil
                        }
                    },
                    onOpen: {
                        if draggedFavoriteID == nil { onOpen(favorite) }
                    },
                    onRemove: { onRemove(favorite) }
                )
                .offset(x: offset(for: favorite.id))
                .animation(
                    draggedFavoriteID == favorite.id ? nil : .easeOut(duration: 0.16),
                    value: hoverTargetID
                )
                .overlay {
                    if draggedFavoriteID == favorite.id || hoverTargetID == favorite.id {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.accentColor.opacity(0.13))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.accentColor.opacity(0.7), lineWidth: 1)
                            }
                            .allowsHitTesting(false)
                    }
                }
                .zIndex(draggedFavoriteID == favorite.id ? 20 : 0)
                .transaction { transaction in
                    if draggedFavoriteID == favorite.id && !isSettlingDrag {
                        transaction.animation = nil
                        transaction.disablesAnimations = true
                    }
                }
                .simultaneousGesture(reorderGesture(for: favorite))
            }
        }
        .frame(
            width: CGFloat(favorites.count) * itemStep,
            height: 30,
            alignment: .bottomLeading
        )
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(isRegionHovered ? 0.14 : 0))
        }
        .contentShape(Rectangle())
        .onHover { isRegionHovered = $0 }
        .animation(.easeOut(duration: 0.16), value: isRegionHovered)
        .onChange(of: hoverFeedbackEnabled) { enabled in
            if !enabled { hoveredFavoriteID = nil }
        }
    }

    private func reorderGesture(for favorite: FavoriteApp) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { value in
                guard !isSettlingDrag, !NSEvent.modifierFlags.contains(.option) else { return }
                if draggedFavoriteID == nil {
                    draggedFavoriteID = favorite.id
                    dragStartIDs = favorites.map(\.id)
                    onDragChanged(true)
                }
                guard draggedFavoriteID == favorite.id else { return }
                dragTranslation = value.translation.width
                updateDropTarget()
            }
            .onEnded { _ in
                guard draggedFavoriteID == favorite.id else { return }
                finishReorder()
            }
    }

    private func updateDropTarget() {
        guard let draggedFavoriteID,
              let keys = dragStartIDs,
              let sourceIndex = keys.firstIndex(of: draggedFavoriteID),
              dragTranslation != 0 else {
            clearDropTarget()
            return
        }

        let sourceCenter = CGFloat(sourceIndex) * itemStep + buttonSize / 2 + dragTranslation
        let targetIndex: Int?
        let direction: AppDragDirection
        if dragTranslation < 0 {
            direction = .left
            targetIndex = keys.indices
                .filter { $0 < sourceIndex && sourceCenter <= CGFloat($0) * itemStep + buttonSize / 2 }
                .min()
        } else {
            direction = .right
            targetIndex = keys.indices
                .filter { $0 > sourceIndex && sourceCenter >= CGFloat($0) * itemStep + buttonSize / 2 }
                .max()
        }
        guard let targetIndex else {
            clearDropTarget()
            return
        }

        let candidate = PendingDropCandidate(appKey: keys[targetIndex], direction: direction)
        if hoverTargetID == candidate.appKey { return }
        if pendingCandidate == candidate { return }

        hoverTargetID = nil
        pendingCandidate = candidate
        let token = UUID()
        pendingToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard pendingToken == token,
                  pendingCandidate == candidate,
                  self.draggedFavoriteID == draggedFavoriteID,
                  !isSettlingDrag else { return }
            hoverTargetID = candidate.appKey
            pendingCandidate = nil
            pendingToken = nil
        }
    }

    private func clearDropTarget() {
        pendingCandidate = nil
        pendingToken = nil
        hoverTargetID = nil
    }

    private func finishReorder() {
        isSettlingDrag = true
        pendingCandidate = nil
        pendingToken = nil
        if let sourceID = draggedFavoriteID,
           let targetID = hoverTargetID,
           var keys = dragStartIDs,
           let sourceIndex = keys.firstIndex(of: sourceID) {
            keys.remove(at: sourceIndex)
            if let targetIndex = keys.firstIndex(of: targetID) {
                let insertionIndex = sourceIndex > targetIndex ? targetIndex : targetIndex + 1
                keys.insert(sourceID, at: insertionIndex)
                if let newIndex = keys.firstIndex(of: sourceID) {
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        dragTranslation -= CGFloat(newIndex - sourceIndex) * itemStep
                        hoverTargetID = nil
                        onReorder(keys)
                    }
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            withAnimation(.easeOut(duration: 0.18)) {
                dragTranslation = 0
                hoverTargetID = nil
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            draggedFavoriteID = nil
            dragStartIDs = nil
            isSettlingDrag = false
            onDragChanged(false)
        }
    }

    private func offset(for id: String) -> CGFloat {
        if id == draggedFavoriteID { return dragTranslation }
        guard let draggedFavoriteID,
              let hoverTargetID,
              let keys = dragStartIDs,
              let sourceIndex = keys.firstIndex(of: draggedFavoriteID),
              let targetIndex = keys.firstIndex(of: hoverTargetID),
              let itemIndex = keys.firstIndex(of: id) else { return 0 }
        if sourceIndex < targetIndex, (sourceIndex + 1...targetIndex).contains(itemIndex) {
            return -itemStep
        }
        if targetIndex < sourceIndex, (targetIndex..<sourceIndex).contains(itemIndex) {
            return itemStep
        }
        return 0
    }
}

private struct FavoriteAppButton: View {
    let favorite: FavoriteApp
    let isHovered: Bool
    let onHoverChange: (Bool) -> Void
    let onOpen: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Button(action: onOpen) {
            FavoriteApplicationIcon(favorite: favorite)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .onHover(perform: onHoverChange)
        .overlay(alignment: .bottom) {
            Capsule()
                .fill(Color.accentColor.opacity(isHovered ? 0.85 : 0))
                .frame(width: 15, height: 2)
                .offset(y: 2)
        }
        .brightness(isHovered ? 0.08 : 0)
        .animation(.easeOut(duration: 0.16), value: isHovered)
        .help("打开 \(favorite.applicationName)；拖动可调整收藏顺序")
        .contextMenu {
            Button("取消收藏", role: .destructive, action: onRemove)
        }
        .accessibilityLabel("收藏：\(favorite.applicationName)")
        .accessibilityHint("点击打开 App；拖动可调整收藏顺序")
    }

}

private struct FavoriteApplicationIcon: View {
    let favorite: FavoriteApp

    var body: some View {
        if isCalendar {
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                CalendarFavoriteIcon(date: timeline.date)
            }
            .frame(width: 26, height: 26)
        } else {
            Image(nsImage: applicationIcon)
                .resizable()
                .frame(width: 26, height: 26)
        }
    }

    private var isCalendar: Bool {
        favorite.bundleIdentifier == "com.apple.iCal"
            || favorite.applicationName.localizedCaseInsensitiveContains("Calendar")
            || favorite.applicationName.contains("日历")
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

private struct CalendarFavoriteIcon: View {
    let date: Date

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(red: 0.92, green: 0.22, blue: 0.20))
                .frame(height: 8)
                .overlay(alignment: .top) {
                    HStack(spacing: 8) {
                        Capsule().fill(.white.opacity(0.95)).frame(width: 1.5, height: 4).offset(y: -1)
                        Capsule().fill(.white.opacity(0.95)).frame(width: 1.5, height: 4).offset(y: -1)
                    }
                }
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.16, green: 0.17, blue: 0.19))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(2)
        .background(.white, in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.black.opacity(0.12), lineWidth: 0.6))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

private struct WindowActionMenu: View {
    let favoriteActionTitle: String
    let onToggleFavorite: () -> Void
    let onShowAppWindows: () -> Void
    let onBlockWindowType: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(favoriteActionTitle, action: onToggleFavorite)
            Divider()
            Button("显示该 App 的所有窗口", action: onShowAppWindows)
            Divider()
            Button("屏蔽此类窗口", action: onBlockWindowType)
            Divider()
            Button("关闭此窗口", role: .destructive, action: onClose)
        }
        .padding(10)
    }
}
