import AppKit
import SwiftUI

struct TaskbarView: View {
    let windows: [WindowModel]
    let recentApplications: [FavoriteApp]
    let runningApplicationIDs: Set<String>
    let isAccessibilityTrusted: Bool
    let onRequestPermission: () -> Void
    let onSelect: (WindowModel) -> Void
    let onMinimizeAll: () -> Void
    let onOpenTrash: () -> Void
    let onShowAppWindows: (WindowModel) -> Void
    let onBlockWindowType: (WindowModel) -> Void
    let onClose: (WindowModel) -> Void
    let onOpenFavorite: (FavoriteApp) -> Void
    let onQuitRecentApp: (FavoriteApp) -> Void
    let showsFavorites: Bool
    let showsControls: Bool
    let showsEmptyState: Bool
    @ObservedObject var settings: SettingsStore
    @ObservedObject var trashStatus: TrashStatusService
    let onSettingsChanged: () -> Void
    let onAppDragChanged: (Bool) -> Void
    let onFavoriteHoverActivity: (Bool) -> Void
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
        .preferredColorScheme(settings.appearancePreference(in: settings.layoutMode).colorScheme)
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
                            runningApplicationIDs: runningApplicationIDs,
                            shortcutIndices: settings.layoutMode == .taskbar
                                ? settings.activeFavoriteShortcutIndices : [],
                            hoverFeedbackEnabled: settings.favoriteMagnificationEnabled,
                            sizeScale: taskbarPanelScale,
                            onOpen: onOpenFavorite,
                            onRemove: { favorite in
                                settings.removeFavorite(favorite)
                                onSettingsChanged()
                            },
                            onReorder: { settings.reorderFavorites($0) },
                            onDragChanged: onAppDragChanged,
                            onHoverActivity: onFavoriteHoverActivity
                        )
                        .padding(.horizontal, FavoriteMagnificationLayout.sideClearance(for: taskbarPanelScale))
                        .padding(.leading, 6 * taskbarPanelScale)

                        if !recentApplications.isEmpty || !windows.isEmpty {
                            Divider()
                                .frame(height: 22 * taskbarPanelScale)
                        }
                    }

                    if !recentApplications.isEmpty {
                        RecentApplicationDockView(
                            applications: recentApplications,
                            runningApplicationIDs: runningApplicationIDs,
                            sizeScale: taskbarPanelScale,
                            isDark: settings.appearance == .dark,
                            onOpen: onOpenFavorite,
                            onQuit: onQuitRecentApp
                        )

                        if !windows.isEmpty {
                            Divider()
                                .frame(height: 22 * taskbarPanelScale)
                        }
                    }

                    if windows.isEmpty && showsEmptyState {
                        taskbarDragArea
                    } else if !windows.isEmpty {
                        let itemWidth = taskbarItemWidth(for: geometry.size.width)
                        HStack(spacing: taskbarItemSpacing) {
                            ForEach(appGroups) { group in
                                HStack(spacing: taskbarItemSpacing) {
                                    if settings.layoutMode == .dockCompanion,
                                       group.windows.count >= settings.dockCompanionCollapseThreshold {
                                        FusionCollapsedAppView(
                                            windows: group.windows,
                                            availableWidth: itemWidth,
                                            itemHeight: taskbarItemHeight,
                                            contentScale: taskbarContentScale,
                                            nonSelectedItemTransparency: settings.nonSelectedItemTransparency,
                                            shortcutLabel: shortcutLabel(for: group.windows.first(where: \.isFocused) ?? group.windows[0]),
                                            onSelect: onSelect
                                        )
                                        .frame(width: itemWidth, height: taskbarItemHeight)
                                        .simultaneousGesture(taskbarReorderGesture(for: group.windows[0], itemWidth: itemWidth))
                                    } else {
                                    ForEach(group.windows) { window in
                                        Button {
                                            onSelect(window)
                                        } label: {
                                            WindowTaskItemView(
                                                window: window,
                                                availableWidth: itemWidth,
                                                appearance: effectiveAppearance,
                                                isDockCompanion: settings.layoutMode == .dockCompanion,
                                                isTaskbarMode: settings.layoutMode == .taskbar,
                                                showApplicationName: settings.showApplicationName,
                                                highlightStyle: settings.taskItemHighlightStyle,
                                                nonSelectedItemTransparency: settings.nonSelectedItemTransparency,
                                                shortcutLabel: shortcutLabel(for: window),
                                                itemHeight: taskbarItemHeight,
                                                contentScale: taskbarContentScale,
                                                taskbarFontSize: settings.taskbarItemFontSize,
                                                onShowAppWindows: { onShowAppWindows(window) },
                                                onBlockWindowType: { onBlockWindowType(window) },
                                                onClose: { onClose(window) },
                                                onToggleFavorite: { toggleFavorite(window) },
                                                favoriteActionTitle: favoriteMenuTitle(for: window)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .frame(width: itemWidth, height: taskbarItemHeight)
                                        .contentShape(Rectangle())
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
                                        .accessibilityValue(window.isFocused ? "当前焦点窗口" : "非焦点窗口")
                                    }
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
                        .padding(
                            .leading,
                            (showsFavorites && !settings.favoriteApps.isEmpty) || !recentApplications.isEmpty
                                ? 0
                                : (settings.layoutMode == .dockCompanion ? 2 : 8) * taskbarPanelScale
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                }

                if showsControls && (settings.layoutMode != .dockCompanion || settings.dockCompanionShowsBottomBar) {
                    HStack(spacing: 2 * taskbarPanelScale) {
                        if settings.layoutMode == .taskbar {
                            TaskbarTrashButton(
                                isFull: trashStatus.isFull,
                                scale: taskbarContentScale,
                                action: onOpenTrash
                            )
                        } else {
                            TaskbarControlButton(
                                systemImage: "minus.rectangle",
                                help: "最小化全部窗口",
                                scale: taskbarContentScale,
                                isTaskbarMode: false,
                                action: onMinimizeAll
                            )
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
                    .padding(.horizontal, 8 * taskbarPanelScale)
                }
                if showsControls && settings.layoutMode == .taskbar && !settings.favoriteFolders.isEmpty {
                    Divider()
                        .frame(height: 22 * taskbarPanelScale)
                    FavoriteFolderDockView(
                        folders: settings.favoriteFolders,
                        sizeScale: taskbarPanelScale
                    )
                    .padding(.trailing, 7 * taskbarPanelScale)
                }
                if showsControls && settings.layoutMode == .taskbar {
                    TaskbarControlButton(
                        systemImage: "minus.rectangle",
                        help: "最小化全部窗口",
                        scale: taskbarContentScale,
                        isTaskbarMode: true,
                        action: onMinimizeAll
                    )
                    .padding(.trailing, 8 * taskbarPanelScale)
                }
            }
            .frame(height: taskbarBaseHeight)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .background(alignment: .bottom) {
            if settings.layoutMode != .dockCompanion || settings.dockCompanionShowsBottomBar {
                FusionDockTileSurface(
                    cornerRadius: settings.layoutMode == .dockCompanion
                        ? 14 * min(taskbarContentScale, 1.3) : 11,
                    isHighlighted: false
                )
                .frame(height: taskbarBaseHeight)
            }
        }
        .shadow(
            color: settings.layoutMode == .dockCompanion && settings.dockCompanionShowsBottomBar ? Color.black.opacity(0.16) : .clear,
            radius: 9,
            y: 4
        )
        .padding(.horizontal, 2)
        .padding(.top, 2)
        .padding(.bottom, settings.layoutMode == .taskbar ? 0 : 2)
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
            controlsAndPadding = (showsControls ? 84 : 16) * taskbarPanelScale
        }
        let favoriteWidth = !showsFavorites || settings.favoriteApps.isEmpty
            ? 0
            : (CGFloat(settings.favoriteApps.count) * 32 + CGFloat(max(settings.favoriteApps.count - 1, 0)) * 2 + 14) * taskbarPanelScale
                + 2 * FavoriteMagnificationLayout.sideClearance(for: taskbarPanelScale)
        let recentApplicationWidth: CGFloat = recentApplications.isEmpty ? 0 : 46 * taskbarPanelScale
        let favoriteFolderWidth: CGFloat = settings.layoutMode == .taskbar && showsControls
            ? CGFloat(settings.favoriteFolders.count) * 34 * taskbarPanelScale
                + (settings.favoriteFolders.isEmpty ? 0 : 12 * taskbarPanelScale)
            : 0
        let displayCount = settings.layoutMode == .dockCompanion
            ? FusionDisplayPolicy.displayCount(
                appKeys: windows.map(\.appKey),
                collapseThreshold: settings.dockCompanionCollapseThreshold
            )
            : windows.count
        let totalSpacing = CGFloat(max(displayCount - 1, 0)) * taskbarItemSpacing
        let available = max(
            totalWidth - controlsAndPadding - favoriteWidth - recentApplicationWidth - favoriteFolderWidth - totalSpacing,
            0
        )
        let maximumWidth = settings.layoutMode == .dockCompanion
            ? DockCompanionSizing.maximumItemWidth(for: settings.dockCompanionHeight)
            : 148 * taskbarPanelScale
        let minimumWidth = settings.layoutMode == .dockCompanion
            ? DockCompanionSizing.minimumItemWidth(for: settings.dockCompanionHeight)
            : 27 * taskbarPanelScale
        return min(maximumWidth, max(minimumWidth, available / CGFloat(displayCount)))
    }

    private var taskbarBaseHeight: CGFloat {
        settings.layoutMode == .dockCompanion ? settings.dockCompanionHeight : settings.taskbarHeight
    }

    private var taskbarPanelScale: CGFloat {
        settings.layoutMode == .dockCompanion
            ? DockCompanionSizing.scale(for: settings.dockCompanionHeight)
            : settings.taskbarHeight / SettingsStore.defaultTaskbarHeight
    }

    private var taskbarContentScale: CGFloat {
        settings.layoutMode == .dockCompanion
            ? DockCompanionSizing.contentScale(for: settings.dockCompanionHeight)
            : settings.taskbarHeight / SettingsStore.defaultTaskbarHeight
    }

    private var taskbarItemHeight: CGFloat {
        guard settings.layoutMode == .dockCompanion else { return settings.taskbarHeight - 7 * taskbarPanelScale }
        return settings.dockCompanionShowsBottomBar
            ? DockCompanionSizing.itemHeight(for: settings.dockCompanionHeight)
            : settings.dockCompanionHeight
    }

    private var taskbarItemSpacing: CGFloat {
        settings.layoutMode == .dockCompanion
            ? DockCompanionSizing.itemSpacing(for: settings.dockCompanionHeight)
            : 4 * taskbarPanelScale
    }

    private var appReorderAnimation: Animation {
        settings.layoutMode == .taskbar
            ? .spring(response: 0.30, dampingFraction: 0.86)
            : .easeOut(duration: 0.16)
    }

    private var effectiveAppearance: TaskbarAppearance {
        settings.resolvedAppearance(in: settings.layoutMode)
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
        settings.orderedWindows(windows)
    }

    private func shortcutLabel(for window: WindowModel) -> String? {
        guard settings.layoutMode != .matrix else { return nil }
        let isCompanionLeft = settings.layoutMode == .dockCompanion && !showsControls
        let labels = isCompanionLeft
            ? OptionWindowHotKeyMonitor.favoriteShortcutLabels.prefix(8).map { $0 }
            : settings.layoutMode == .dockCompanion
                ? OptionWindowHotKeyMonitor.windowShortcutLabels.prefix(5).map { $0 }
                : OptionWindowHotKeyMonitor.windowShortcutLabels
        let registeredIndices = isCompanionLeft
            ? settings.activeFavoriteShortcutIndices : settings.activeTaskbarShortcutIndices
        let shortcutWindows = settings.layoutMode == .dockCompanion
            ? fusionShortcutWindows : orderedWindows
        guard let index = shortcutWindows.prefix(labels.count)
                .firstIndex(where: { $0.id == window.id }),
              registeredIndices.contains(index + 1) else { return nil }
        return labels[index]
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

    private var fusionShortcutWindows: [WindowModel] {
        var result: [WindowModel] = []
        for group in appGroups {
            if group.windows.count >= settings.dockCompanionCollapseThreshold {
                result.append(group.windows.first(where: \.isFocused) ?? group.windows[0])
            } else {
                result.append(contentsOf: group.windows)
            }
        }
        return result
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

private struct FusionDockTileSurface: View {
    let cornerRadius: CGFloat
    let isHighlighted: Bool

    var body: some View {
        ZStack {
            if #available(macOS 26, *) {
                NativeFusionGlassView(cornerRadius: cornerRadius)
                    .allowsHitTesting(false)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.regularMaterial)
                    .opacity(0.62)
            }
            if isHighlighted {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.24), lineWidth: 0.7)
                .allowsHitTesting(false)
        }
    }
}

/// Use native Liquid Glass on macOS 26+ and a material fallback on older systems.
@available(macOS 26, *)
private struct NativeFusionGlassView: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSGlassEffectView {
        let glass = NSGlassEffectView(frame: .zero)
        glass.style = .clear
        glass.cornerRadius = cornerRadius
        return glass
    }

    func updateNSView(_ nsView: NSGlassEffectView, context: Context) {
        nsView.cornerRadius = cornerRadius
    }
}

private struct FusionCollapsedAppView: View {
    let windows: [WindowModel]
    let availableWidth: CGFloat
    let itemHeight: CGFloat
    let contentScale: CGFloat
    let nonSelectedItemTransparency: Double
    let shortcutLabel: String?
    let onSelect: (WindowModel) -> Void
    @State private var isShowingWindows = false
    @State private var isHovered = false

    var body: some View {
        let representative = windows.first(where: \.isFocused) ?? windows[0]
        let compact = availableWidth < 75 * contentScale
        Button { isShowingWindows.toggle() } label: {
            HStack(spacing: 7 * contentScale) {
                Image(nsImage: representative.applicationIcon
                    ?? NSImage(named: NSImage.applicationIconName)
                    ?? NSImage(size: NSSize(width: 24, height: 24)))
                    .resizable()
                    .frame(width: (compact ? 18 : 22) * contentScale,
                           height: (compact ? 18 : 22) * contentScale)
                    .overlay(alignment: .topTrailing) {
                        if compact {
                            Text(shortcutLabel ?? "\(windows.count)")
                                .font(.system(size: 8 * contentScale, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(2 * contentScale)
                                .background(Color.accentColor, in: Circle())
                                .offset(x: 5 * contentScale, y: -5 * contentScale)
                        } else if let shortcutLabel {
                            Text(shortcutLabel)
                                .font(.system(size: 10 * contentScale, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 14 * contentScale, height: 14 * contentScale)
                                .background(Color.accentColor, in: Circle())
                                .offset(x: 4 * contentScale, y: -4 * contentScale)
                        }
                    }
                if !compact {
                    Text(representative.applicationName)
                        .font(.system(size: 11.5 * contentScale, weight: .semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !compact {
                    Text("\(windows.count)")
                        .font(.system(size: 10 * contentScale, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5 * contentScale)
                        .padding(.vertical, 2 * contentScale)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                }
            }
            .padding(.horizontal, (compact ? 2 : 7) * contentScale)
            .frame(maxWidth: .infinity, minHeight: itemHeight, maxHeight: itemHeight)
            .background {
                FusionDockTileSurface(
                    cornerRadius: 11 * contentScale,
                    isHighlighted: isHovered || windows.contains(where: \.isFocused)
                )
            }
            .overlay(alignment: .bottom) {
                if windows.contains(where: \.isFocused) {
                    Circle().fill(Color.primary.opacity(0.76))
                        .frame(width: 4 * contentScale, height: 4 * contentScale)
                        .padding(.bottom, 2 * contentScale)
                }
            }
        }
        .buttonStyle(.plain)
        .opacity(windows.contains(where: \.isFocused) ? 1 : 1 - nonSelectedItemTransparency)
        .onHover { isHovered = $0 }
        .help("\(representative.applicationName)：\(windows.count) 个窗口，点击展开")
        .accessibilityLabel("\(representative.applicationName)，\(windows.count) 个窗口")
        .popover(isPresented: $isShowingWindows, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(representative.applicationName)
                    .font(.headline)
                    .padding(.bottom, 4)
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(windows) { window in
                            Button {
                                isShowingWindows = false
                                onSelect(window)
                            } label: {
                                HStack(spacing: 8) {
                                    Text(window.title)
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    if window.isMinimized {
                                        Image(systemName: "minus.circle")
                                            .foregroundStyle(.secondary)
                                    }
                                    if window.isFocused {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            .help(window.title)
                        }
                    }
                }
                .frame(maxHeight: 360)
            }
            .padding(12)
            .frame(width: 280)
        }
    }
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
    var shortcutLabel: String? = nil
    var itemHeight: CGFloat = 31
    var contentScale: CGFloat = 1
    var taskbarFontSize: CGFloat = SettingsStore.defaultTaskbarItemFontSize
    let onShowAppWindows: () -> Void
    let onBlockWindowType: () -> Void
    let onClose: () -> Void
    let onToggleFavorite: () -> Void
    let favoriteActionTitle: String
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: availableWidth < textVisibilityWidth ? 0 : 7 * contentScale) {
            Image(nsImage: window.applicationIcon ?? fallbackIcon)
                .resizable()
                .frame(width: iconSize, height: iconSize)
                .overlay(alignment: .topTrailing) {
                    if let shortcutLabel {
                        Text(shortcutLabel)
                            .font(.system(size: 10 * contentScale, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 14 * contentScale, height: 14 * contentScale)
                            .background(Color.accentColor, in: Circle())
                            .offset(x: 4 * contentScale, y: -4 * contentScale)
                            .accessibilityHidden(true)
                    }
                }
            if availableWidth >= textVisibilityWidth {
                VStack(alignment: .leading, spacing: 0) {
                    Text(window.title)
                        .font(.system(
                            size: (isTaskbarMode ? taskbarFontSize : (showApplicationName ? 11.5 : 10.5)) * contentScale,
                            weight: .medium
                        ))
                        .foregroundStyle(titleColor)
                        .lineLimit(showApplicationName ? 1 : 2)
                        .fixedSize(horizontal: false, vertical: !showApplicationName)
                    if showApplicationName && availableWidth >= subtitleVisibilityWidth {
                        Text(window.applicationName)
                            .font(.system(
                                size: (isTaskbarMode ? min(10.5, taskbarFontSize * 9.5 / 12) : 9.5) * contentScale,
                                weight: .medium
                            ))
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
                if isDockCompanion {
                    FusionDockTileSurface(
                        cornerRadius: 11 * contentScale,
                        isHighlighted: isHovered || window.isFocused
                    )
                } else if isTaskbarMode {
                    RoundedRectangle(cornerRadius: 7 * contentScale)
                        .fill(taskbarGlassItemBackground)
                    RoundedRectangle(cornerRadius: 7 * contentScale)
                        .stroke(Color.white.opacity(isHovered || window.isFocused ? 0.28 : 0.10), lineWidth: 0.7)
                } else {
                    RoundedRectangle(cornerRadius: 7 * contentScale)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 7 * contentScale)
                        .fill(cardSurfaceColor)
                    RoundedRectangle(cornerRadius: 7 * contentScale)
                        .fill(itemBaseBackground)
                }
            }
        }
        .overlay(alignment: isTaskbarMode ? .bottomLeading : .bottom) {
            if window.isFocused {
                if isDockCompanion {
                    Circle()
                        .fill(Color.primary.opacity(0.76))
                        .frame(width: 4 * contentScale, height: 4 * contentScale)
                        .padding(.bottom, 2 * contentScale)
                } else {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: isTaskbarMode ? iconSize : nil, height: 3 * contentScale)
                        .padding(.leading, isTaskbarMode
                            ? (availableWidth < textVisibilityWidth ? 3 : 8) * contentScale : 0)
                        .padding(.horizontal, isTaskbarMode ? 0 : 9 * contentScale)
                        .padding(.bottom, contentScale)
                }
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
    }

    private var fallbackIcon: NSImage {
        NSImage(named: NSImage.applicationIconName) ?? NSImage(size: NSSize(width: 24, height: 24))
    }

    private var itemBaseBackground: Color {
        if isTaskbarMode && appearance == .dark {
            guard isHovered || window.isFocused else { return .clear }
            switch highlightStyle {
            case .systemAccent:
                return Color.accentColor.opacity(window.isFocused ? 0.22 : 0.12)
            case .white:
                return Color.white.opacity(window.isFocused ? 0.20 : 0.11)
            }
        }
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

    private var taskbarGlassItemBackground: Color {
        if appearance == .dark {
            return Color.white.opacity(window.isFocused ? 0.18 : (isHovered ? 0.12 : 0.05))
        }
        return Color.white.opacity(window.isFocused ? 0.30 : (isHovered ? 0.20 : 0.08))
    }

    private var cardSurfaceColor: Color {
        if isDockCompanion && window.bundleIdentifier == "com.apple.finder" {
            return appearance == .dark ? Color.black.opacity(0.06) : Color.white.opacity(0.64)
        }
        return appearance == .dark ? Color.black.opacity(0.08) : Color.white.opacity(0.82)
    }

    private var titleColor: Color {
        if isTaskbarMode && appearance == .light {
            return Color(red: 0.20, green: 0.29, blue: 0.39)
                .opacity(window.isFocused ? 0.96 : 0.84)
        }
        return appearance == .dark ? Color.white.opacity(0.96) : Color.black.opacity(0.88)
    }

    private var subtitleColor: Color {
        if isTaskbarMode && appearance == .light {
            return Color(red: 0.34, green: 0.43, blue: 0.53).opacity(0.85)
        }
        return appearance == .dark ? Color.white.opacity(isTaskbarMode ? 0.88 : 0.62) : Color.black.opacity(0.56)
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

private struct TaskbarTrashButton: View {
    let isFull: Bool
    let scale: CGFloat
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            icon
                .resizable()
                .interpolation(.high)
                .frame(width: 24 * scale, height: 24 * scale)
                .frame(width: 28 * scale, height: 28 * scale)
                .contentShape(Rectangle())
                .background(
                    Color.primary.opacity(isHovered ? 0.09 : 0),
                    in: RoundedRectangle(cornerRadius: 7 * scale)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.16), value: isHovered)
        .help(isFull ? "打开废纸篓（非空）" : "打开废纸篓（空）")
        .accessibilityLabel(isFull ? "打开废纸篓，非空" : "打开废纸篓，空")
    }

    private var icon: Image {
        let imageName = NSImage.Name(isFull ? "NSTrashFull" : "NSTrashEmpty")
        if let image = NSImage(named: imageName) { return Image(nsImage: image) }
        return Image(systemName: "trash")
    }
}

private struct RecentApplicationDockView: View {
    let applications: [FavoriteApp]
    let runningApplicationIDs: Set<String>
    let sizeScale: CGFloat
    let isDark: Bool
    let onOpen: (FavoriteApp) -> Void
    let onQuit: (FavoriteApp) -> Void
    @State private var isShowingApplications = false
    @State private var hoveredApplicationID: String?

    var body: some View {
        Button {
            isShowingApplications.toggle()
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 17 * sizeScale, weight: .medium))
                Text("\(applications.count)")
                    .font(.system(size: 10 * sizeScale, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundStyle(isDark ? Color.white.opacity(0.82) : Color(red: 0.30, green: 0.39, blue: 0.49))
            .frame(width: 38 * sizeScale, height: 30 * sizeScale)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("最近打开的 App（\(applications.count) 个）")
        .accessibilityLabel("最近打开的 App，\(applications.count) 个；点击展开列表")
        .popover(isPresented: $isShowingApplications, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("最近打开的 App")
                    .font(.headline)
                    .padding(.bottom, 4)
                ForEach(applications) { application in
                    HStack(spacing: 6) {
                        Button {
                            hoveredApplicationID = nil
                            isShowingApplications = false
                            onOpen(application)
                        } label: {
                            HStack(spacing: 9) {
                                FavoriteApplicationIcon(favorite: application)
                                    .frame(width: 26, height: 26)
                                Text(application.applicationName)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .frame(minWidth: 190, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("打开 \(application.applicationName)")

                        if runningApplicationIDs.contains(application.id) {
                            Button {
                                onQuit(application)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 22, height: 26)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("退出 \(application.applicationName)")
                            .accessibilityLabel("退出 \(application.applicationName)")
                        } else {
                            Color.clear.frame(width: 22, height: 26)
                        }
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background {
                        if hoveredApplicationID == application.id {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color.accentColor.opacity(isDark ? 0.40 : 0.26))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 7)
                                        .stroke(Color.accentColor.opacity(0.95), lineWidth: 1.2)
                                }
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.accentColor)
                                        .frame(width: 3, height: 18)
                                        .padding(.leading, 2)
                                }
                        }
                    }
                    .contentShape(Rectangle())
                    .onHover { isHovered in
                        hoveredApplicationID = isHovered ? application.id :
                            (hoveredApplicationID == application.id ? nil : hoveredApplicationID)
                    }
                }
            }
            .padding(12)
        }
        .onChange(of: isShowingApplications) { isShowing in
            if !isShowing { hoveredApplicationID = nil }
        }
    }
}

private struct FavoriteFolderDockView: View {
    let folders: [FavoriteFolder]
    let sizeScale: CGFloat

    var body: some View {
        HStack(spacing: 4 * sizeScale) {
            ForEach(folders) { folder in
                Button {
                    NSWorkspace.shared.open(folder.url)
                } label: {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: folder.path))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 26 * sizeScale, height: 26 * sizeScale)
                        .frame(width: 30 * sizeScale, height: 30 * sizeScale)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("打开收藏文件夹：\(folder.name)")
                .accessibilityLabel("打开收藏文件夹：\(folder.name)")
            }
        }
    }
}

private struct FavoriteDockView: View {
    let favorites: [FavoriteApp]
    let runningApplicationIDs: Set<String>
    let shortcutIndices: Set<Int>
    let hoverFeedbackEnabled: Bool
    let sizeScale: CGFloat
    let onOpen: (FavoriteApp) -> Void
    let onRemove: (FavoriteApp) -> Void
    let onReorder: ([String]) -> Void
    let onDragChanged: (Bool) -> Void
    let onHoverActivity: (Bool) -> Void
    @State private var visualController = FavoriteDockVisualController()
    @State private var draggedFavoriteID: String?
    @State private var dragStartIDs: [String]?
    @State private var dragTranslation: CGFloat = 0
    @State private var hoverTargetID: String?
    @State private var pendingCandidate: PendingDropCandidate?
    @State private var pendingToken: UUID?
    @State private var isSettlingDrag = false

    private var itemStep: CGFloat { 32 * sizeScale }
    private var buttonSize: CGFloat { 30 * sizeScale }
    private var hoverSafetyWidth: CGFloat { 12 * sizeScale }

    var body: some View {
        HStack(spacing: itemStep - buttonSize) {
            ForEach(Array(favorites.enumerated()), id: \.element.id) { index, favorite in
                FavoriteAppButton(
                    favorite: favorite,
                    isRunning: runningApplicationIDs.contains(favorite.id),
                    shortcutLabel: shortcutIndices.contains(index + 1)
                        ? OptionWindowHotKeyMonitor.favoriteShortcutLabels[index] : nil,
                    sizeScale: sizeScale,
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
            height: SettingsStore.defaultTaskbarHeight * sizeScale,
            alignment: .center
        )
        .background {
            FavoriteDockVisualView(
                favorites: favorites,
                runningApplicationIDs: runningApplicationIDs,
                sizeScale: sizeScale,
                dragOffsets: favorites.map { offset(for: $0.id) },
                controller: visualController
            )
            .allowsHitTesting(false)
        }
        .overlay {
            FavoriteHoverTrackingView { location in
                let isHovered = location != nil
                onHoverActivity(hoverFeedbackEnabled && draggedFavoriteID == nil && isHovered)
                guard hoverFeedbackEnabled, draggedFavoriteID == nil, let location else {
                    visualController.updatePointer(nil)
                    return
                }
                let rowWidth = CGFloat(favorites.count) * itemStep
                let pointerX = min(max(location.x - hoverSafetyWidth, itemStep / 2),
                                   rowWidth - itemStep / 2)
                visualController.updatePointer(pointerX)
            }
            .frame(width: CGFloat(favorites.count) * itemStep + 2 * hoverSafetyWidth)
        }
        .contentShape(Rectangle())
        .onChange(of: hoverFeedbackEnabled) { enabled in
            if !enabled {
                onHoverActivity(false)
                visualController.updatePointer(nil)
            }
        }
        .onDisappear {
            onHoverActivity(false)
            visualController.updatePointer(nil)
        }
    }

    private func reorderGesture(for favorite: FavoriteApp) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { value in
                guard !isSettlingDrag, !NSEvent.modifierFlags.contains(.option) else { return }
                if draggedFavoriteID == nil {
                    draggedFavoriteID = favorite.id
                    visualController.updatePointer(nil)
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

@MainActor
private final class FavoriteDockVisualController {
    weak var view: FavoriteDockVisualView.DrawingView?

    func updatePointer(_ x: CGFloat?) {
        view?.updatePointer(x)
    }
}

private struct FavoriteDockVisualView: NSViewRepresentable {
    let favorites: [FavoriteApp]
    let runningApplicationIDs: Set<String>
    let sizeScale: CGFloat
    let dragOffsets: [CGFloat]
    let controller: FavoriteDockVisualController

    func makeNSView(context: Context) -> DrawingView {
        let view = DrawingView()
        controller.view = view
        view.configure(
            favorites: favorites,
            runningApplicationIDs: runningApplicationIDs,
            sizeScale: sizeScale,
            dragOffsets: dragOffsets
        )
        return view
    }

    func updateNSView(_ view: DrawingView, context: Context) {
        controller.view = view
        view.configure(
            favorites: favorites,
            runningApplicationIDs: runningApplicationIDs,
            sizeScale: sizeScale,
            dragOffsets: dragOffsets
        )
    }

    static func dismantleNSView(_ view: DrawingView, coordinator: ()) {
        view.updatePointer(nil)
    }

    final class DrawingView: NSView {
        private struct EntryState {
            let iconPosition: CGPoint
            let iconScale: CGFloat
            let indicatorPosition: CGPoint
            let indicatorScale: CGFloat
        }

        private var iconLayers: [CALayer] = []
        private var indicatorLayers: [CALayer] = []
        private var favoriteIDs: [String] = []
        private var runningApplicationIDs: Set<String> = []
        private var sizeScale: CGFloat = 1
        private var dragOffsets: [CGFloat] = []
        private var pointerX: CGFloat?
        private var entryStates: [EntryState] = []
        private var entryStartedAt: CFTimeInterval?
        private var entryTimer: Timer?

        deinit { entryTimer?.invalidate() }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.masksToBounds = false
        }

        required init?(coder: NSCoder) { nil }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            updateIndicatorColors()
        }

        func configure(
            favorites: [FavoriteApp],
            runningApplicationIDs: Set<String>,
            sizeScale: CGFloat,
            dragOffsets: [CGFloat]
        ) {
            let ids = favorites.map(\.id)
            let favoritesChanged = ids != favoriteIDs
            let indicatorsChanged = favoritesChanged || self.runningApplicationIDs != runningApplicationIDs
            if favoritesChanged {
                stopEntryAnimation()
                iconLayers.forEach { $0.removeFromSuperlayer() }
                indicatorLayers.forEach { $0.removeFromSuperlayer() }
                indicatorLayers = favorites.map { _ in
                    let indicator = CALayer()
                    indicator.zPosition = 0.5
                    layer?.addSublayer(indicator)
                    return indicator
                }
                iconLayers = favorites.map { favorite in
                    let icon = CALayer()
                    icon.contents = FavoriteApplicationIcon.image(for: favorite)
                        .cgImage(forProposedRect: nil, context: nil, hints: nil)
                    icon.contentsGravity = .resizeAspect
                    icon.magnificationFilter = .linear
                    icon.anchorPoint = CGPoint(x: 0.5, y: 0)
                    icon.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
                    layer?.addSublayer(icon)
                    return icon
                }
                favoriteIDs = ids
            }
            guard indicatorsChanged || self.sizeScale != sizeScale || self.dragOffsets != dragOffsets else { return }
            self.runningApplicationIDs = runningApplicationIDs
            self.sizeScale = sizeScale
            self.dragOffsets = dragOffsets
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let iconSize = FavoriteMagnificationLayout.iconSize * sizeScale
            for icon in iconLayers {
                icon.bounds = CGRect(x: 0, y: 0, width: iconSize, height: iconSize)
            }
            for indicator in indicatorLayers {
                indicator.bounds = CGRect(x: 0, y: 0, width: 5 * sizeScale, height: 5 * sizeScale)
                indicator.cornerRadius = 2.5 * sizeScale
            }
            if indicatorsChanged { updateIndicatorColors() }
            CATransaction.commit()
            updateLayers(animated: false)
        }

        private func updateIndicatorColors() {
            for indicator in indicatorLayers {
                indicator.backgroundColor = NSColor(calibratedWhite: 0.82, alpha: 0.96).cgColor
            }
        }

        func updatePointer(_ x: CGFloat?) {
            guard pointerX != x else { return }
            if pointerX == nil && x != nil {
                entryStates = zip(iconLayers, indicatorLayers).map { icon, indicator in
                    let visibleIcon = icon.presentation() ?? icon
                    let visibleIndicator = indicator.presentation() ?? indicator
                    return EntryState(
                        iconPosition: visibleIcon.position,
                        iconScale: visibleIcon.transform.m11,
                        indicatorPosition: visibleIndicator.position,
                        indicatorScale: visibleIndicator.transform.m11
                    )
                }
                (iconLayers + indicatorLayers).forEach { $0.removeAllAnimations() }
                entryStartedAt = CACurrentMediaTime()
                entryTimer?.invalidate()
                let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                    self?.advanceEntryAnimation()
                }
                RunLoop.main.add(timer, forMode: .common)
                entryTimer = timer
            } else if x == nil {
                stopEntryAnimation()
            }
            let animate = x == nil
            pointerX = x
            updateLayers(animated: animate)
        }

        private func advanceEntryAnimation() {
            guard let entryStartedAt else { stopEntryAnimation(); return }
            if CACurrentMediaTime() - entryStartedAt >= 0.18 {
                stopEntryAnimation()
            }
            updateLayers(animated: false)
        }

        private func stopEntryAnimation() {
            entryTimer?.invalidate()
            entryTimer = nil
            entryStartedAt = nil
            entryStates = []
        }

        private func updateLayers(animated: Bool) {
            let layout = FavoriteMagnificationLayout(
                count: iconLayers.count,
                pointerX: pointerX,
                sizeScale: sizeScale
            )
            let entryProgress: CGFloat
            if let entryStartedAt {
                let linear = min(1, max(0, CGFloat((CACurrentMediaTime() - entryStartedAt) / 0.18)))
                entryProgress = linear * linear * (3 - 2 * linear)
            } else {
                entryProgress = 1
            }
            CATransaction.begin()
            CATransaction.setDisableActions(!animated)
            if animated {
                CATransaction.setAnimationDuration(0.14)
                CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
            }
            for (index, icon) in iconLayers.enumerated() {
                let scale = layout.scales[index]
                let isRunning = runningApplicationIDs.contains(favoriteIDs[index])
                let geometry = layout.visualGeometry(
                    at: index,
                    sizeScale: sizeScale,
                    dragOffset: dragOffsets.indices.contains(index) ? dragOffsets[index] : 0,
                    isNoWindow: true
                )
                let targetIconPosition = CGPoint(
                    x: geometry.centerX,
                    y: geometry.iconBottomY
                )
                let entry = entryStates.indices.contains(index) ? entryStates[index] : nil
                let displayedScale = entry.map {
                    $0.iconScale + (scale - $0.iconScale) * entryProgress
                } ?? scale
                icon.position = entry.map {
                    CGPoint(
                        x: $0.iconPosition.x + (targetIconPosition.x - $0.iconPosition.x) * entryProgress,
                        y: $0.iconPosition.y + (targetIconPosition.y - $0.iconPosition.y) * entryProgress
                    )
                } ?? targetIconPosition
                icon.transform = CATransform3DMakeScale(displayedScale, displayedScale, 1)
                icon.zPosition = displayedScale

                let indicator = indicatorLayers[index]
                let targetIndicatorPosition = CGPoint(
                    x: geometry.centerX,
                    y: geometry.indicatorCenterY
                )
                let indicatorScale = 1 + (scale - 1) * 0.5
                indicator.position = entry.map {
                    CGPoint(
                        x: $0.indicatorPosition.x + (targetIndicatorPosition.x - $0.indicatorPosition.x) * entryProgress,
                        y: $0.indicatorPosition.y + (targetIndicatorPosition.y - $0.indicatorPosition.y) * entryProgress
                    )
                } ?? targetIndicatorPosition
                let displayedIndicatorScale = entry.map {
                    $0.indicatorScale + (indicatorScale - $0.indicatorScale) * entryProgress
                } ?? indicatorScale
                indicator.transform = CATransform3DMakeScale(displayedIndicatorScale, displayedIndicatorScale, 1)
                indicator.opacity = isRunning ? 1 : 0
            }
            CATransaction.commit()
        }
    }
}

private struct FavoriteHoverTrackingView: NSViewRepresentable {
    let onLocationChange: (CGPoint?) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onLocationChange = onLocationChange
        return view
    }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.onLocationChange = onLocationChange
    }

    final class TrackingView: NSView {
        var onLocationChange: ((CGPoint?) -> Void)?
        private var hoverArea: NSTrackingArea?
        private var pendingLocation: CGPoint?
        private var isPointerInside = false
        private var isUpdateScheduled = false

        override func updateTrackingAreas() {
            if let hoverArea { removeTrackingArea(hoverArea) }
            let area = NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways,
                          .enabledDuringMouseDrag, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            hoverArea = area
            super.updateTrackingAreas()
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func mouseEntered(with event: NSEvent) { updateLocation(for: event) }
        override func mouseMoved(with event: NSEvent) { updateLocation(for: event) }
        override func mouseDragged(with event: NSEvent) { updateLocation(for: event) }
        override func mouseExited(with event: NSEvent) {
            isPointerInside = false
            pendingLocation = nil
            onLocationChange?(nil)
        }

        private func updateLocation(for event: NSEvent) {
            let location = convert(event.locationInWindow, from: nil)
            guard bounds.contains(location) else {
                if isPointerInside { onLocationChange?(nil) }
                isPointerInside = false
                pendingLocation = nil
                return
            }
            isPointerInside = true
            pendingLocation = location
            guard !isUpdateScheduled else { return }
            isUpdateScheduled = true
            // Keep at most one pending layer update per display half-frame. Fast
            // mice can generate far more events than Core Animation can present.
            let displayFPS = max(60, window?.screen?.maximumFramesPerSecond
                ?? NSScreen.main?.maximumFramesPerSecond ?? 60)
            let updateFPS = min(displayFPS * 2, 240)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / Double(updateFPS)) { [weak self] in
                guard let self else { return }
                self.isUpdateScheduled = false
                if self.isPointerInside {
                    self.onLocationChange?(self.pendingLocation)
                }
            }
        }
    }
}

private struct FavoriteAppButton: View {
    let favorite: FavoriteApp
    let isRunning: Bool
    let shortcutLabel: String?
    let sizeScale: CGFloat
    let onOpen: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Button(action: onOpen) {
            Color.clear
                .frame(width: 30 * sizeScale, height: 30 * sizeScale)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: 30 * sizeScale, height: 30 * sizeScale)
        .contentShape(Rectangle())
        .overlay(alignment: .topTrailing) {
            if let shortcutLabel {
                Text(shortcutLabel)
                    .font(.system(size: 10 * sizeScale, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 14 * sizeScale, height: 14 * sizeScale)
                    .background(Color.accentColor, in: Circle())
                    .offset(x: 3, y: -3)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .help(isRunning
            ? "\(favorite.applicationName) 正在运行，指示灯已亮；点击激活"
            : "打开 \(favorite.applicationName)；拖动可调整收藏顺序")
        .contextMenu {
            Button("取消收藏", role: .destructive, action: onRemove)
        }
        .accessibilityLabel("收藏：\(favorite.applicationName)")
        .accessibilityHint("点击打开 App；拖动可调整收藏顺序")
    }

}

private struct FavoriteApplicationIcon: View {
    let favorite: FavoriteApp
    var size: CGFloat = 26
    private static let iconCache = NSCache<NSString, NSImage>()

    var body: some View {
        Image(nsImage: Self.image(for: favorite))
            .resizable()
            .renderingMode(.original)
            .interpolation(.high)
            .frame(width: size, height: size)
    }

    fileprivate static func image(for favorite: FavoriteApp) -> NSImage {
        let cacheKey = "\(favorite.id)|\(favorite.bundlePath ?? "")" as NSString
        if let cached = Self.iconCache.object(forKey: cacheKey) { return cached }
        let workspace = NSWorkspace.shared
        let icon: NSImage
        if let bundleIdentifier = favorite.bundleIdentifier,
           let url = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            icon = workspace.icon(forFile: url.path)
        } else if let bundlePath = favorite.bundlePath {
            icon = workspace.icon(forFile: bundlePath)
        } else {
            icon = NSImage(named: NSImage.applicationIconName)
                ?? NSImage(size: NSSize(width: 24, height: 24))
        }
        Self.iconCache.setObject(icon, forKey: cacheKey)
        return icon
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
