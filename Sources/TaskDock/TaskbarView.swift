import AppKit
import SwiftUI

@MainActor
final class RecentAppPopoverState: ObservableObject {
    @Published var isPresented = false
    @Published var displayedApplications: [FavoriteApp] = []
    @Published var favoritedInCurrentListIDs: Set<String> = []

    func open(applications: [FavoriteApp]) {
        displayedApplications = applications
        favoritedInCurrentListIDs = []
        isPresented = true
    }
}

struct TaskbarView: View {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    let windows: [WindowModel]
    let recentApplications: [FavoriteApp]
    let recentAppPopoverState: RecentAppPopoverState
    let runningApplicationIDs: Set<String>
    @ObservedObject var favoriteBadges: FavoriteBadgeStore
    let isAccessibilityTrusted: Bool
    let onRequestPermission: () -> Void
    let onSelect: (WindowModel) -> Void
    let onMinimizeAll: () -> Void
    let onOpenTrash: () -> Void
    let onOpenFolder: (FavoriteFolder) -> Void
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
    let onRecentPopoverVisibilityChanged: (Bool) -> Void
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
    @State private var favoriteMagnificationActive = false

    private var reducesTaskbarMotion: Bool {
        settings.layoutMode == .taskbar && (settings.taskbarReduceMotion || systemReduceMotion)
    }

    private func isCollapsed(_ group: AppWindowGroup) -> Bool {
        if settings.layoutMode == .dockCompanion {
            return group.windows.count >= settings.dockCompanionCollapseThreshold
        }
        return settings.layoutMode == .taskbar && settings.taskbarCollapseSameAppWindows
            && group.windows.count >= 3
    }

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
            HStack(spacing: settings.layoutMode == .taskbar ? 0 : 8) {
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
                    if showsFavorites {
                        FavoriteDockView(
                            favorites: settings.favoriteApps,
                            folders: settings.layoutMode == .taskbar && showsControls
                                ? settings.favoriteFolders : [],
                            showsTrash: settings.layoutMode == .taskbar && showsControls,
                            isTrashFull: trashStatus.isFull,
                            runningApplicationIDs: runningApplicationIDs,
                            badgeLabels: favoriteBadges.badges,
                            shortcutIndices: settings.layoutMode == .taskbar
                                ? settings.activeFavoriteShortcutIndices : [],
                            hoverFeedbackEnabled: settings.favoriteMagnificationEnabled,
                            reducesMotion: reducesTaskbarMotion,
                            hitRegionWidth: settings.layoutMode == .taskbar
                                ? TaskbarFavoriteLaneLayout.flowWidth(
                                    contentWidth: TaskbarFavoriteLaneLayout.contentWidth(
                                        appCount: settings.favoriteApps.count,
                                        folderCount: showsControls ? settings.favoriteFolders.count : 0,
                                        showsTrash: showsControls),
                                    limit: settings.taskbarFavoriteFlowWidth) * taskbarPanelScale
                                : nil,
                            showsHoverLabel: settings.layoutMode == .taskbar,
                            sizeScale: taskbarPanelScale,
                            onOpen: onOpenFavorite,
                            onQuit: onQuitRecentApp,
                            onOpenTrash: onOpenTrash,
                            onOpenFolder: onOpenFolder,
                            onRemove: { favorite in
                                settings.removeFavorite(favorite)
                                onSettingsChanged()
                            },
                            onReorder: { settings.reorderFavorites($0) },
                            onRemoveFolder: { folder in
                                settings.removeFavoriteFolder(folder)
                                onSettingsChanged()
                            },
                            onReorderFolders: { settings.reorderFavoriteFolders($0) },
                            onDropURLs: { urls, insertion in
                                var added = false
                                var appIndex = insertion.appIndex
                                var folderIndex = insertion.folderIndex
                                for url in urls {
                                    if url.pathExtension.lowercased() == "app" {
                                        if settings.addFavorite(applicationURL: url, at: appIndex) {
                                            added = true
                                            appIndex += 1
                                        }
                                    } else {
                                        if settings.addFavoriteFolder(url, at: folderIndex) {
                                            added = true
                                            folderIndex += 1
                                        }
                                    }
                                }
                                if added { onSettingsChanged() }
                                return added
                            },
                            onDragChanged: onAppDragChanged,
                            onHoverActivity: onFavoriteHoverActivity,
                            onMagnificationChange: { active in
                                if favoriteMagnificationActive != active {
                                    favoriteMagnificationActive = active
                                }
                            }
                        )
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(width: settings.layoutMode == .taskbar
                            ? TaskbarFavoriteLaneLayout.flowWidth(
                                contentWidth: TaskbarFavoriteLaneLayout.contentWidth(
                                    appCount: settings.favoriteApps.count,
                                    folderCount: showsControls ? settings.favoriteFolders.count : 0,
                                    showsTrash: showsControls),
                                limit: settings.taskbarFavoriteFlowWidth) * taskbarPanelScale
                            : nil, alignment: .leading)
                        .zIndex(settings.layoutMode == .taskbar ? 2 : 0)

                        if !recentApplications.isEmpty || !windows.isEmpty {
                            Divider()
                                .frame(height: 22 * taskbarPanelScale)
                        }
                    }

                    if !recentApplications.isEmpty {
                        RecentApplicationDockView(
                            applications: recentApplications,
                            popoverState: recentAppPopoverState,
                            runningApplicationIDs: runningApplicationIDs,
                            sizeScale: taskbarPanelScale,
                            isDark: settings.appearance == .dark,
                            blurredByFavorites: favoriteMagnificationActive,
                            onOpen: onOpenFavorite,
                            onQuit: onQuitRecentApp,
                            onFavorite: { settings.addFavorite($0) },
                            onUnfavorite: { settings.removeFavorite($0) },
                            onPopoverVisibilityChanged: onRecentPopoverVisibilityChanged
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
                                    if settings.layoutMode == .dockCompanion, isCollapsed(group) {
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
                                    } else if settings.layoutMode == .taskbar, isCollapsed(group) {
                                        TaskbarCollapsedAppView(
                                            windows: group.windows,
                                            availableWidth: itemWidth,
                                            itemHeight: taskbarItemHeight,
                                            contentScale: taskbarContentScale,
                                            appearance: effectiveAppearance,
                                            taskbarFontSize: settings.taskbarItemFontSize,
                                            nonSelectedItemTransparency: settings.nonSelectedItemTransparency,
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
                                                reducesMotion: reducesTaskbarMotion,
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
                            showsFavorites || !recentApplications.isEmpty
                                ? 0
                                : (settings.layoutMode == .dockCompanion ? 2 : 8) * taskbarPanelScale
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                }

                if showsControls && settings.layoutMode == .dockCompanion
                    && settings.dockCompanionShowsBottomBar {
                    HStack(spacing: 2 * taskbarPanelScale) {
                        TaskbarControlButton(
                            systemImage: "minus.rectangle",
                            help: "最小化全部窗口",
                            scale: taskbarContentScale,
                            isTaskbarMode: false,
                            action: onMinimizeAll
                        )
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
                    .padding(.horizontal, 8 * taskbarPanelScale)
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
        .padding(.leading, settings.layoutMode == .taskbar
            ? settings.taskbarSideInset : 0)
        .padding(.trailing, settings.layoutMode == .taskbar
            ? settings.taskbarSideInset : 0)
        .background(alignment: .bottom) {
            if settings.layoutMode != .dockCompanion || settings.dockCompanionShowsBottomBar {
                FusionDockTileSurface(
                    cornerRadius: settings.layoutMode == .dockCompanion
                        ? 14 * min(taskbarContentScale, 1.3) : 11,
                    isHighlighted: false
                )
                .frame(height: taskbarBaseHeight)
                .padding(.leading, settings.layoutMode == .taskbar
                    ? settings.taskbarSideInset : 0)
                .padding(.trailing, settings.layoutMode == .taskbar
                    ? settings.taskbarSideInset : 0)
            }
        }
        .shadow(
            color: settings.layoutMode == .dockCompanion && settings.dockCompanionShowsBottomBar ? Color.black.opacity(0.16) : .clear,
            radius: 9,
            y: 4
        )
        .padding(.horizontal, settings.layoutMode == .taskbar ? 0 : 2)
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
            controlsAndPadding = (showsControls ? 40 : 16) * taskbarPanelScale
        }
        let favoriteItemCount = settings.favoriteApps.count
            + (settings.layoutMode == .taskbar && showsControls ? 1 + settings.favoriteFolders.count : 0)
        let favoriteWidth: CGFloat
        if !showsFavorites || favoriteItemCount == 0 {
            favoriteWidth = 0
        } else if settings.layoutMode == .taskbar {
            favoriteWidth = TaskbarFavoriteLaneLayout.flowWidth(
                contentWidth: TaskbarFavoriteLaneLayout.contentWidth(
                    appCount: settings.favoriteApps.count,
                    folderCount: showsControls ? settings.favoriteFolders.count : 0,
                    showsTrash: showsControls),
                limit: settings.taskbarFavoriteFlowWidth) * taskbarPanelScale
        } else {
            favoriteWidth = (CGFloat(favoriteItemCount) * 32
                + CGFloat(max(favoriteItemCount - 1, 0)) * 2 + 14) * taskbarPanelScale
                + FavoriteMagnificationLayout.idleSideClearance(for: taskbarPanelScale)
        }
        let recentApplicationWidth: CGFloat = recentApplications.isEmpty ? 0 : 40 * taskbarPanelScale
        let displayCount = appGroups.reduce(0) { $0 + (isCollapsed($1) ? 1 : $1.windows.count) }
        let totalSpacing = CGFloat(max(displayCount - 1, 0)) * taskbarItemSpacing
        let available = max(
            totalWidth - controlsAndPadding - favoriteWidth - recentApplicationWidth - totalSpacing,
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
        reducesTaskbarMotion ? .easeOut(duration: 0.08) : settings.layoutMode == .taskbar
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
                    .onEnded { _ in onPanelDragEnded() },
                including: settings.layoutMode == .matrix ? .all : .none
            )
            .help(settings.layoutMode == .matrix ? "拖动矩阵面板" : "")
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
                guard settings.layoutMode == .matrix,
                      NSEvent.modifierFlags.contains(.option) else { return }
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
        var slot = 0
        for group in appGroups {
            let count = isCollapsed(group) ? 1 : group.windows.count
            keys.append(group.id)
            minXs.append(CGFloat(slot) * step)
            maxXs.append(CGFloat(slot + count - 1) * step + itemWidth)
            slot += count
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

private struct TaskbarCollapsedAppView: View {
    let windows: [WindowModel]
    let availableWidth: CGFloat
    let itemHeight: CGFloat
    let contentScale: CGFloat
    let appearance: TaskbarAppearance
    let taskbarFontSize: CGFloat
    let nonSelectedItemTransparency: Double
    let onSelect: (WindowModel) -> Void
    @State private var isShowingWindows = false

    var body: some View {
        let representative = windows.first(where: \.isFocused) ?? windows[0]
        let compact = availableWidth < 70 * contentScale
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
                            Text("\(windows.count)")
                                .font(.system(size: 8 * contentScale, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(2 * contentScale)
                                .background(Color.accentColor, in: Circle())
                                .offset(x: 4 * contentScale, y: -4 * contentScale)
                        }
                    }
                if !compact {
                    Text(representative.applicationName)
                        .font(.system(size: taskbarFontSize * contentScale, weight: .medium))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(windows.count)")
                        .font(.system(size: 10 * contentScale, weight: .bold, design: .rounded))
                        .padding(.horizontal, 5 * contentScale)
                        .padding(.vertical, 2 * contentScale)
                        .background(Color.primary.opacity(0.12), in: Capsule())
                }
            }
            .padding(.horizontal, (compact ? 2 : 7) * contentScale)
            .frame(maxWidth: .infinity, minHeight: itemHeight, maxHeight: itemHeight)
            .background {
                RoundedRectangle(cornerRadius: 7 * contentScale)
                    .fill(Color.white.opacity(appearance == .dark ? 0.14 : 0.24))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7 * contentScale)
                            .stroke(Color.white.opacity(0.24), lineWidth: 0.7)
                    }
            }
            .overlay(alignment: .bottomLeading) {
                if windows.contains(where: \.isFocused) {
                    Capsule().fill(Color.accentColor)
                        .frame(width: (compact ? 18 : 22) * contentScale,
                               height: 3 * contentScale)
                        .padding(.leading, (compact ? 2 : 7) * contentScale)
                        .padding(.bottom, contentScale)
                }
            }
        }
        .buttonStyle(.plain)
        .opacity(windows.contains(where: \.isFocused) ? 1 : 1 - nonSelectedItemTransparency)
        .help("\(representative.applicationName)：\(windows.count) 个窗口，点击选择")
        .accessibilityLabel("\(representative.applicationName)，\(windows.count) 个窗口，点击选择")
        .popover(isPresented: $isShowingWindows, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(representative.applicationName).font(.headline)
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(windows) { window in
                            Button {
                                isShowingWindows = false
                                onSelect(window)
                            } label: {
                                HStack(spacing: 8) {
                                    Text(window.title).lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    if window.isMinimized { Image(systemName: "minus.circle") }
                                    if window.isFocused { Image(systemName: "checkmark") }
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
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
    var reducesMotion: Bool = false
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
        .scaleEffect(isHovered && !reducesMotion ? 1.012 : 1.0)
        .opacity(window.isFocused ? 1 : 1 - nonSelectedItemTransparency)
        .shadow(color: isHovered ? Color.black.opacity(appearance == .dark ? 0.28 : 0.12) : .clear, radius: 4, y: 1)
        .zIndex(isHovered ? 2 : (window.isFocused ? 1 : 0))
        .animation(
            reducesMotion ? .easeOut(duration: 0.07)
                : isTaskbarMode ? .easeInOut(duration: 0.24) : .easeOut(duration: 0.12),
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

private struct RecentApplicationDockView: View {
    let applications: [FavoriteApp]
    @ObservedObject var popoverState: RecentAppPopoverState
    let runningApplicationIDs: Set<String>
    let sizeScale: CGFloat
    let isDark: Bool
    let blurredByFavorites: Bool
    let onOpen: (FavoriteApp) -> Void
    let onQuit: (FavoriteApp) -> Void
    let onFavorite: (FavoriteApp) -> Bool
    let onUnfavorite: (FavoriteApp) -> Void
    let onPopoverVisibilityChanged: (Bool) -> Void
    @State private var hoveredApplicationID: String?
    @State private var pointerLocationWhenOpened: NSPoint?

    var body: some View {
        Button {
            if !popoverState.isPresented {
                popoverState.open(applications: applications)
                pointerLocationWhenOpened = NSEvent.mouseLocation
                hoveredApplicationID = nil
            } else {
                popoverState.isPresented = false
            }
        } label: {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 17 * sizeScale, weight: .medium))
                .foregroundStyle(isDark ? Color.white.opacity(0.82) : Color(red: 0.30, green: 0.39, blue: 0.49))
                .blur(radius: blurredByFavorites ? 7 * sizeScale : 0)
                .opacity(blurredByFavorites ? 0.38 : 1)
                .animation(.easeOut(duration: 0.14), value: blurredByFavorites)
                .frame(width: 32 * sizeScale, height: 30 * sizeScale)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("最近打开的 App")
        .accessibilityLabel("最近打开的 App；点击展开列表")
        .popover(isPresented: $popoverState.isPresented, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("最近打开的 App")
                    .font(.headline)
                    .padding(.bottom, 4)
                ForEach([true, false], id: \.self) { isRunning in
                    let groupedApplications = popoverState.displayedApplications.filter {
                        runningApplicationIDs.contains($0.id) == isRunning
                    }
                    if !groupedApplications.isEmpty {
                        Text(isRunning ? "正在运行" : "未运行")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                            .padding(.leading, 5)
                    }
                    ForEach(groupedApplications) { application in
                        HStack(spacing: 6) {
                            Button {
                                hoveredApplicationID = nil
                                popoverState.isPresented = false
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

                            Button {
                                if popoverState.favoritedInCurrentListIDs.contains(application.id) {
                                    onUnfavorite(application)
                                    popoverState.favoritedInCurrentListIDs.remove(application.id)
                                } else if onFavorite(application) {
                                    popoverState.favoritedInCurrentListIDs.insert(application.id)
                                }
                            } label: {
                                Image(systemName: popoverState.favoritedInCurrentListIDs.contains(application.id) ? "star.fill" : "star")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.primary)
                                    .frame(width: 22, height: 26)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .opacity(hoveredApplicationID == application.id
                                || popoverState.favoritedInCurrentListIDs.contains(application.id) ? 1 : 0)
                            .allowsHitTesting(hoveredApplicationID == application.id
                                || popoverState.favoritedInCurrentListIDs.contains(application.id))
                            .accessibilityHidden(hoveredApplicationID != application.id
                                && !popoverState.favoritedInCurrentListIDs.contains(application.id))
                            .help(popoverState.favoritedInCurrentListIDs.contains(application.id)
                                ? "取消收藏 \(application.applicationName)" : "收藏 \(application.applicationName)")
                            .accessibilityLabel(popoverState.favoritedInCurrentListIDs.contains(application.id)
                                ? "取消收藏 \(application.applicationName)" : "收藏 \(application.applicationName)")

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
                            if isHovered {
                                let currentLocation = NSEvent.mouseLocation
                                let hasMovedSinceOpening = pointerLocationWhenOpened.map {
                                    hypot(currentLocation.x - $0.x, currentLocation.y - $0.y) > 4
                                } ?? true
                                if hasMovedSinceOpening {
                                    hoveredApplicationID = application.id
                                }
                            } else if hoveredApplicationID == application.id {
                                hoveredApplicationID = nil
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
        .onChange(of: popoverState.isPresented) { isShowing in
            onPopoverVisibilityChanged(isShowing)
            if !isShowing {
                hoveredApplicationID = nil
                pointerLocationWhenOpened = nil
            }
        }
    }
}

private enum FavoriteShelfItem: Identifiable {
    case app(FavoriteApp)
    case separator
    case trash(isFull: Bool)
    case folder(FavoriteFolder)
    case insertionGap(String)

    var id: String {
        switch self {
        case .app(let app): return app.id
        case .separator: return "utility:separator"
        case .trash: return "utility:trash"
        case .folder(let folder): return "utility:folder:\(folder.id)"
        case .insertionGap(let id): return "drop-gap:\(id)"
        }
    }

    var name: String {
        switch self {
        case .app(let app): return app.applicationName
        case .separator: return ""
        case .trash: return "废纸篓"
        case .folder(let folder): return folder.name
        case .insertionGap: return ""
        }
    }

    var app: FavoriteApp? {
        if case .app(let app) = self { return app }
        return nil
    }

    var isRemovable: Bool {
        switch self {
        case .app, .folder: return true
        case .separator, .trash, .insertionGap: return false
        }
    }

    var trashIsFull: Bool? {
        if case .trash(let isFull) = self { return isFull }
        return nil
    }

    var isSeparator: Bool {
        if case .separator = self { return true }
        return false
    }

    var icon: NSImage {
        switch self {
        case .app(let app): return FavoriteApplicationIcon.image(for: app)
        case .separator: return NSImage()
        case .trash(let isFull):
            return NSImage(named: NSImage.Name(isFull ? "NSTrashFull" : "NSTrashEmpty"))
                ?? NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
                ?? NSImage()
        case .folder(let folder): return NSWorkspace.shared.icon(forFile: folder.path)
        case .insertionGap: return NSImage()
        }
    }
}

private struct FavoriteDockView: View {
    let favorites: [FavoriteApp]
    let folders: [FavoriteFolder]
    let showsTrash: Bool
    let isTrashFull: Bool
    let runningApplicationIDs: Set<String>
    let badgeLabels: [String: String]
    let shortcutIndices: Set<Int>
    let hoverFeedbackEnabled: Bool
    let reducesMotion: Bool
    let hitRegionWidth: CGFloat?
    let showsHoverLabel: Bool
    let sizeScale: CGFloat
    let onOpen: (FavoriteApp) -> Void
    let onQuit: (FavoriteApp) -> Void
    let onOpenTrash: () -> Void
    let onOpenFolder: (FavoriteFolder) -> Void
    let onRemove: (FavoriteApp) -> Void
    let onReorder: ([String]) -> Void
    let onRemoveFolder: (FavoriteFolder) -> Void
    let onReorderFolders: ([String]) -> Void
    let onDropURLs: ([URL], FavoriteShelfInsertion) -> Bool
    let onDragChanged: (Bool) -> Void
    let onHoverActivity: (Bool) -> Void
    let onMagnificationChange: (Bool) -> Void
    @State private var visualController = FavoriteDockVisualController()
    @State private var draggedFavoriteID: String?
    @State private var dragStartIDs: [String]?
    @State private var dragTranslation: CGFloat = 0
    @State private var dragPointerX: CGFloat?
    @State private var dragStartLayoutOffset: CGFloat = 0
    @State private var hoverTargetID: String?
    @State private var isSettlingDrag = false
    @State private var isPointerInside = false
    @State private var externalInsertion: FavoriteShelfInsertion?

    private var itemStep: CGFloat { 32 * sizeScale }
    private var buttonSize: CGFloat { 30 * sizeScale }
    private var hoverSafetyWidth: CGFloat {
        FavoriteMagnificationLayout.sideClearance(for: sizeScale)
    }
    private var peakScale: CGFloat { reducesMotion ? 1.35 : FavoriteMagnificationLayout.maximumScale }
    private var items: [FavoriteShelfItem] {
        var apps = favorites.map(FavoriteShelfItem.app)
        var folderItems = folders.map(FavoriteShelfItem.folder)
        if let insertion = externalInsertion {
            apps.insert(contentsOf: (0..<insertion.appCount).map { .insertionGap("app:\($0)") },
                        at: min(insertion.appIndex, apps.count))
            folderItems.insert(contentsOf: (0..<insertion.folderCount).map { .insertionGap("folder:\($0)") },
                               at: min(insertion.folderIndex, folderItems.count))
        }
        return apps + (!apps.isEmpty && (showsTrash || !folderItems.isEmpty) ? [.separator] : [])
            + folderItems + (showsTrash ? [.trash(isFull: isTrashFull)] : [])
    }

    var body: some View {
        HStack(spacing: itemStep - buttonSize) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if item.isSeparator {
                    Color.clear
                        .frame(width: 2 * sizeScale, height: buttonSize)
                        .accessibilityHidden(true)
                } else if case .insertionGap = item {
                    Color.clear.frame(width: buttonSize, height: buttonSize)
                        .accessibilityHidden(true)
                } else {
                    FavoriteShelfButton(
                    item: item,
                    isRunning: item.app.map { runningApplicationIDs.contains($0.id) } ?? false,
                    badgeLabel: item.app.flatMap { badgeLabels[$0.id] },
                    shortcutLabel: item.app != nil && shortcutIndices.contains(index + 1)
                        ? OptionWindowHotKeyMonitor.favoriteShortcutLabels[index] : nil,
                    sizeScale: sizeScale,
                    onOpen: {
                        guard draggedFavoriteID == nil else { return }
                        switch item {
                        case .app(let app): onOpen(app)
                        case .separator, .insertionGap: break
                        case .trash: onOpenTrash()
                        case .folder(let folder): onOpenFolder(folder)
                        }
                    }
                    )
                    .offset(x: offset(for: item.id))
                    .animation(
                        draggedFavoriteID == item.id ? nil
                            : .easeOut(duration: reducesMotion ? 0.07 : 0.16),
                        value: hoverTargetID
                    )
                    .zIndex(draggedFavoriteID == item.id ? 20 : 0)
                    .transaction { transaction in
                        if draggedFavoriteID == item.id && !isSettlingDrag {
                            transaction.animation = nil
                            transaction.disablesAnimations = true
                        }
                    }
                }
            }
        }
        .frame(
            width: CGFloat(items.count) * itemStep
                - CGFloat(items.filter(\.isSeparator).count) * 28 * sizeScale,
            height: SettingsStore.defaultTaskbarHeight * sizeScale,
            alignment: .center
        )
        .background {
            FavoriteDockVisualView(
                items: items,
                runningApplicationIDs: runningApplicationIDs,
                badgeLabels: badgeLabels,
                sizeScale: sizeScale,
                peakScale: peakScale,
                dragOffsets: items.map { offset(for: $0.id) },
                dragSlotShifts: items.map { slotShift(for: $0.id) },
                draggedFavoriteID: draggedFavoriteID,
                isSettlingDrag: isSettlingDrag,
                showsHoverLabel: showsHoverLabel,
                controller: visualController
            )
            .allowsHitTesting(false)
        }
        .overlay {
            FavoriteShelfInteractionView(
                shelfInset: hoverSafetyWidth,
                shelfWidth: hitRegionWidth ?? .greatestFiniteMagnitude,
                previewSize: FavoriteMagnificationLayout.iconSize * peakScale * sizeScale,
                onLocationChange: { location in
                    guard draggedFavoriteID == nil else { return }
                    let isHovered = location != nil
                    let isMagnifying = hoverFeedbackEnabled && draggedFavoriteID == nil && isHovered
                    if isPointerInside != isMagnifying { isPointerInside = isMagnifying }
                    onHoverActivity(hoverFeedbackEnabled && draggedFavoriteID == nil && isHovered)
                    guard hoverFeedbackEnabled, draggedFavoriteID == nil, let location else {
                        visualController.updatePointer(nil)
                        onMagnificationChange(false)
                        return
                    }
                    let pointerX = FavoriteMagnificationLayout.clampedPointerX(
                        trackingX: location.x,
                        count: items.count,
                        sizeScale: sizeScale,
                        separatorCount: items.filter(\.isSeparator).count
                    )
                    visualController.updatePointer(pointerX)
                    onMagnificationChange(true)
                },
                itemAt: { location in
                    visualController.view?.itemID(at: CGPoint(
                        x: location.x - hoverSafetyWidth,
                        y: location.y
                    ))
                },
                iconCenterForItem: { id in
                    guard let center = visualController.view?.iconCenter(for: id) else { return nil }
                    return CGPoint(x: center.x + hoverSafetyWidth, y: center.y)
                },
                iconForItem: { id in items.first { $0.id == id }?.icon },
                canDragItem: { id in items.first { $0.id == id }?.isRemovable ?? false },
                onClick: { id in
                    guard draggedFavoriteID == nil, let item = items.first(where: { $0.id == id }) else { return }
                    switch item {
                    case .app(let app): onOpen(app)
                    case .folder(let folder): onOpenFolder(folder)
                    case .trash: onOpenTrash()
                    case .separator, .insertionGap: break
                    }
                },
                onContextMenu: { id in
                    guard draggedFavoriteID == nil,
                          let item = items.first(where: { $0.id == id }) else { return [] }
                    return contextMenuActions(for: item)
                },
                onDragUpdate: updateDrag,
                onDragEnd: { outside in
                    visualController.view?.hideDraggedItem(nil)
                    if outside { clearDropTarget() }
                    if outside { onMagnificationChange(false) }
                    finishReorder(outside: outside)
                },
                onRemove: { id in
                    guard let item = items.first(where: { $0.id == id }) else { return }
                    clearDropTarget()
                    dragTranslation = 0
                    dragPointerX = nil
                    dragStartLayoutOffset = 0
                    draggedFavoriteID = nil
                    dragStartIDs = nil
                    isSettlingDrag = false
                    visualController.view?.hideDraggedItem(nil)
                    onMagnificationChange(false)
                    remove(item)
                    onDragChanged(false)
                },
                onDropPreview: { urls, x in
                    let incoming = newDropURLs(urls)
                    guard !incoming.isEmpty else { return false }
                    let insertion = insertionTarget(incoming, x: x)
                    if externalInsertion != insertion {
                        withAnimation(.easeOut(duration: 0.16)) { externalInsertion = insertion }
                    }
                    return true
                },
                onDropURLs: { urls, x in
                    let incoming = newDropURLs(urls)
                    guard !incoming.isEmpty else { return false }
                    let insertion = insertionTarget(incoming, x: x)
                    externalInsertion = nil
                    return onDropURLs(incoming, insertion)
                },
                onExternalDragChanged: { active in
                    if !active { withAnimation(.easeOut(duration: 0.16)) { externalInsertion = nil } }
                    onDragChanged(active)
                }
            )
            .frame(width: CGFloat(items.count) * itemStep
                - CGFloat(items.filter(\.isSeparator).count) * 28 * sizeScale
                + 2 * hoverSafetyWidth)
        }
        .contentShape(Rectangle())
        .onChange(of: hoverFeedbackEnabled) { enabled in
            if !enabled {
                isPointerInside = false
                onHoverActivity(false)
                visualController.updatePointer(nil)
                onMagnificationChange(false)
            }
        }
        .onDisappear {
            isPointerInside = false
            onHoverActivity(false)
            visualController.updatePointer(nil)
            onMagnificationChange(false)
        }
    }

    private func remove(_ item: FavoriteShelfItem) {
        switch item {
        case .app(let app): onRemove(app)
        case .folder(let folder): onRemoveFolder(folder)
        case .separator, .trash, .insertionGap: break
        }
    }

    private func contextMenuActions(for item: FavoriteShelfItem) -> [FavoriteShelfMenuAction] {
        func action(_ title: String, _ perform: @escaping () -> Void) -> FavoriteShelfMenuAction {
            FavoriteShelfMenuAction(title: title, perform: perform)
        }

        switch item {
        case .app(let app):
            var actions = [action("打开", { onOpen(app) })]
            if app.bundleIdentifier == "com.apple.finder" {
                let sidebarFavorites = FinderSidebarFavoritesService.favorites()
                if !sidebarFavorites.isEmpty {
                    actions.append(.separator)
                    for favorite in sidebarFavorites {
                        if let url = favorite.url {
                            actions.append(action("打开 \(favorite.name)", {
                                NSWorkspace.shared.open(url)
                            }))
                        } else {
                            actions.append(FavoriteShelfMenuAction(
                                title: "打开 \(favorite.name)（当前不可用）",
                                isEnabled: false,
                                perform: {}
                            ))
                        }
                    }
                    actions.append(.separator)
                }
            }
            let runningApp = NSWorkspace.shared.runningApplications.first { running in
                if let bundleIdentifier = app.bundleIdentifier {
                    return running.bundleIdentifier == bundleIdentifier
                }
                guard let bundlePath = app.bundlePath else { return false }
                return running.bundleURL?.path == bundlePath
            }
            if let runningApp {
                actions.append(action(runningApp.isHidden ? "显示" : "隐藏", {
                    if runningApp.isHidden { onOpen(app) }
                    else { _ = runningApp.hide() }
                }))
                actions.append(action("退出", { onQuit(app) }))
            }
            if let url = runningApp?.bundleURL ?? app.bundlePath.map(URL.init(fileURLWithPath:)),
               FileManager.default.fileExists(atPath: url.path) {
                actions.append(action("在 Finder 中显示", {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }))
            }
            actions.append(.separator)
            actions.append(action("取消收藏", { onRemove(app) }))
            return actions
        case .folder(let folder):
            var actions = [action("打开", { onOpenFolder(folder) })]
            if FileManager.default.fileExists(atPath: folder.path) {
                actions.append(action("在 Finder 中显示", {
                    NSWorkspace.shared.activateFileViewerSelecting([folder.url])
                }))
            }
            actions.append(.separator)
            actions.append(action("取消收藏", { onRemoveFolder(folder) }))
            return actions
        case .trash:
            return [action("打开废纸篓", onOpenTrash)]
        case .separator, .insertionGap:
            return []
        }
    }

    private func newDropURLs(_ urls: [URL]) -> [URL] {
        var seenApps = Set(favorites.map(\.id))
        var seenFolders = Set(folders.map { $0.url.resolvingSymlinksInPath().path })
        return urls.filter { url in
            if url.pathExtension.lowercased() == "app" {
                let bundle = Bundle(url: url)
                let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                let id = bundle?.bundleIdentifier ?? "name:\(name)"
                return seenApps.insert(id).inserted
            }
            return seenFolders.insert(url.path).inserted
        }
    }

    private func insertionTarget(_ urls: [URL], x: CGFloat) -> FavoriteShelfInsertion {
        let appCount = urls.filter { $0.pathExtension.lowercased() == "app" }.count
        return FavoriteShelfInsertion.target(pointerX: x / sizeScale, appTotal: favorites.count,
            folderTotal: folders.count, hasUtilities: showsTrash || !folders.isEmpty || urls.count > appCount,
            incomingApps: appCount, incomingFolders: urls.count - appCount, preview: externalInsertion)
    }

    private func updateDrag(_ id: String, _ translation: CGSize, _ outside: Bool,
                            _ trackingX: CGFloat) {
        guard !isSettlingDrag, let item = items.first(where: { $0.id == id }), item.isRemovable else { return }
        if draggedFavoriteID == nil {
            draggedFavoriteID = id
            dragStartIDs = item.app != nil ? favorites.map(\.id)
                : folders.map { "utility:folder:\($0.id)" }
            let startPointerX = FavoriteMagnificationLayout.clampedPointerX(
                trackingX: trackingX - translation.width, count: items.count,
                sizeScale: sizeScale, separatorCount: items.filter(\.isSeparator).count)
            if let index = items.firstIndex(where: { $0.id == id }) {
                dragStartLayoutOffset = FavoriteMagnificationLayout(
                    count: items.count, pointerX: hoverFeedbackEnabled ? startPointerX : nil,
                    sizeScale: sizeScale,
                    separatorIndices: Set(items.indices.filter { items[$0].isSeparator }),
                    peakScale: peakScale
                ).offsets[index]
            }
            isPointerInside = false
            onHoverActivity(false)
            onDragChanged(true)
        }
        guard draggedFavoriteID == id else { return }
        onDragChanged(true)
        dragTranslation = outside ? 0 : translation.width
        dragPointerX = outside || !hoverFeedbackEnabled ? nil
            : FavoriteMagnificationLayout.clampedPointerX(
                trackingX: trackingX, count: items.count,
                sizeScale: sizeScale, separatorCount: items.filter(\.isSeparator).count)
        visualController.updatePointer(dragPointerX)
        onMagnificationChange(dragPointerX != nil)
        visualController.view?.hideDraggedItem(outside ? id : nil)
        if outside { clearDropTarget() } else { updateDropTarget() }
    }

    private func updateDropTarget() {
        guard let draggedFavoriteID,
              let keys = dragStartIDs,
              let sourceIndex = keys.firstIndex(of: draggedFavoriteID),
              let targetIndex = FavoriteShelfReorderTarget.index(
                source: sourceIndex, count: keys.count, translation: dragTranslation,
                itemStep: itemStep,
                previewIndex: hoverTargetID.flatMap { keys.firstIndex(of: $0) }) else {
            clearDropTarget()
            return
        }
        hoverTargetID = keys[targetIndex]
    }

    private func clearDropTarget() {
        hoverTargetID = nil
    }

    private func finishReorder(outside: Bool) {
        isSettlingDrag = true
        let releaseTargetIndex: Int? = {
            guard !outside, let draggedFavoriteID,
                  let keys = dragStartIDs,
                  let sourceIndex = keys.firstIndex(of: draggedFavoriteID) else { return nil }
            return FavoriteShelfReorderTarget.index(source: sourceIndex, count: keys.count,
                translation: dragTranslation, itemStep: itemStep,
                previewIndex: hoverTargetID.flatMap { keys.firstIndex(of: $0) })
        }()
        let dragLayout = dragPointerX.map { pointerX in
            FavoriteMagnificationLayout(
                count: items.count, pointerX: pointerX, sizeScale: sizeScale,
                separatorIndices: Set(items.indices.filter { items[$0].isSeparator }),
                peakScale: peakScale)
        }
        if let sourceID = draggedFavoriteID,
           let sourceItemIndex = items.firstIndex(where: { $0.id == sourceID }),
           let currentOffset = dragLayout?.offsets[sourceItemIndex] {
            dragTranslation += dragStartLayoutOffset - currentOffset
            dragStartLayoutOffset = currentOffset
        }
        if let sourceID = draggedFavoriteID,
           let targetIndex = releaseTargetIndex,
           var keys = dragStartIDs,
           let sourceIndex = keys.firstIndex(of: sourceID) {
            keys.remove(at: sourceIndex)
            keys.insert(sourceID, at: targetIndex)
            if let newIndex = keys.firstIndex(of: sourceID) {
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    let shift = newIndex - sourceIndex
                    dragTranslation -= CGFloat(shift) * itemStep
                    if let sourceItemIndex = items.firstIndex(where: { $0.id == sourceID }),
                       let newOffset = dragLayout?.offsets[sourceItemIndex + shift] {
                        dragTranslation += dragStartLayoutOffset - newOffset
                        dragStartLayoutOffset = newOffset
                    }
                    hoverTargetID = nil
                    if sourceID.hasPrefix("utility:folder:") {
                        onReorderFolders(keys.map { String($0.dropFirst("utility:folder:".count)) })
                    } else {
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
            dragPointerX = nil
            dragStartLayoutOffset = 0
            isSettlingDrag = false
            isPointerInside = !outside && hoverFeedbackEnabled
            onHoverActivity(isPointerInside)
            onDragChanged(false)
        }
    }

    private func offset(for id: String) -> CGFloat {
        if id == draggedFavoriteID {
            guard let dragPointerX,
                  let index = items.firstIndex(where: { $0.id == id }) else { return dragTranslation }
            let layout = FavoriteMagnificationLayout(
                count: items.count, pointerX: dragPointerX, sizeScale: sizeScale,
                separatorIndices: Set(items.indices.filter { items[$0].isSeparator }),
                peakScale: peakScale)
            return dragTranslation + dragStartLayoutOffset - layout.offsets[index]
        }
        guard let draggedFavoriteID,
              let hoverTargetID,
              let keys = dragStartIDs,
              let sourceIndex = keys.firstIndex(of: draggedFavoriteID),
              let targetIndex = keys.firstIndex(of: hoverTargetID),
              let itemIndex = keys.firstIndex(of: id),
              let visualIndex = items.firstIndex(where: { $0.id == id }) else { return 0 }
        let layout = FavoriteMagnificationLayout(
            count: items.count, pointerX: dragPointerX, sizeScale: sizeScale,
            separatorIndices: Set(items.indices.filter { items[$0].isSeparator }),
            peakScale: peakScale)
        if sourceIndex < targetIndex, (sourceIndex + 1...targetIndex).contains(itemIndex) {
            return layout.reorderPreviewOffset(from: visualIndex,
                to: visualIndex - 1, sizeScale: sizeScale)
        }
        if targetIndex < sourceIndex, (targetIndex..<sourceIndex).contains(itemIndex) {
            return layout.reorderPreviewOffset(from: visualIndex,
                to: visualIndex + 1, sizeScale: sizeScale)
        }
        return 0
    }

    private func slotShift(for id: String) -> Int {
        guard let draggedFavoriteID, id != draggedFavoriteID,
              let hoverTargetID, let keys = dragStartIDs,
              let source = keys.firstIndex(of: draggedFavoriteID),
              let target = keys.firstIndex(of: hoverTargetID),
              let index = keys.firstIndex(of: id) else { return 0 }
        if source < target, (source + 1...target).contains(index) { return -1 }
        if target < source, (target..<source).contains(index) { return 1 }
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
    let items: [FavoriteShelfItem]
    let runningApplicationIDs: Set<String>
    let badgeLabels: [String: String]
    let sizeScale: CGFloat
    let peakScale: CGFloat
    let dragOffsets: [CGFloat]
    let dragSlotShifts: [Int]
    let draggedFavoriteID: String?
    let isSettlingDrag: Bool
    let showsHoverLabel: Bool
    let controller: FavoriteDockVisualController

    func makeNSView(context: Context) -> DrawingView {
        let view = DrawingView()
        controller.view = view
        view.configure(
            items: items,
            runningApplicationIDs: runningApplicationIDs,
            badgeLabels: badgeLabels,
            sizeScale: sizeScale,
            peakScale: peakScale,
            dragOffsets: dragOffsets,
            dragSlotShifts: dragSlotShifts,
            draggedFavoriteID: draggedFavoriteID,
            isSettlingDrag: isSettlingDrag,
            showsHoverLabel: showsHoverLabel
        )
        return view
    }

    func updateNSView(_ view: DrawingView, context: Context) {
        controller.view = view
        view.configure(
            items: items,
            runningApplicationIDs: runningApplicationIDs,
            badgeLabels: badgeLabels,
            sizeScale: sizeScale,
            peakScale: peakScale,
            dragOffsets: dragOffsets,
            dragSlotShifts: dragSlotShifts,
            draggedFavoriteID: draggedFavoriteID,
            isSettlingDrag: isSettlingDrag,
            showsHoverLabel: showsHoverLabel
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
        private var pressOverlayLayers: [String: CALayer] = [:]
        private var indicatorLayers: [CALayer] = []
        private var badgeLayers: [CALayer] = []
        private let hoverLabelLayer = CAShapeLayer()
        private let hoverLabelTextLayer = CATextLayer()
        private var favoriteIDs: [String] = []
        private var favoriteNames: [String] = []
        private var trashIsFull: Bool?
        private var runningApplicationIDs: Set<String> = []
        private var badgeLabels: [String: String] = [:]
        private var sizeScale: CGFloat = 1
        private var peakScale: CGFloat = FavoriteMagnificationLayout.maximumScale
        private var dragOffsets: [CGFloat] = []
        private var slotShiftStarts: [CGFloat] = []
        private var slotShiftTargets: [CGFloat] = []
        private var slotShiftStartedAt: CFTimeInterval?
        private var slotShiftTimer: Timer?
        private var draggedFavoriteID: String?
        private var isSettlingDrag = false
        private var showsHoverLabel = false
        private var displayedHoverLabel: String?
        private var hoverLabelWidth: CGFloat = 0
        private var pointerX: CGFloat?
        private var entryStates: [EntryState] = []
        private var entryStartedAt: CFTimeInterval?
        private var entryTimer: Timer?
        private var mouseDownMonitor: Any?
        private var mouseUpMonitor: Any?
        private var globalMouseUpMonitor: Any?
        private var pressedFavoriteID: String?
        private var pressGeneration = 0

        deinit {
            entryTimer?.invalidate()
            slotShiftTimer?.invalidate()
            if let mouseDownMonitor { NSEvent.removeMonitor(mouseDownMonitor) }
            if let mouseUpMonitor { NSEvent.removeMonitor(mouseUpMonitor) }
            if let globalMouseUpMonitor { NSEvent.removeMonitor(globalMouseUpMonitor) }
        }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.masksToBounds = false
            hoverLabelLayer.zPosition = 30
            hoverLabelLayer.fillColor = NSColor(calibratedWhite: 0.96, alpha: 0.96).cgColor
            hoverLabelLayer.strokeColor = NSColor(calibratedWhite: 0.18, alpha: 0.20).cgColor
            hoverLabelLayer.lineWidth = 0.75
            hoverLabelLayer.shadowColor = NSColor.black.cgColor
            hoverLabelLayer.shadowOpacity = 0.20
            hoverLabelLayer.shadowRadius = 5
            hoverLabelLayer.shadowOffset = CGSize(width: 0, height: -2)
            hoverLabelLayer.opacity = 0
            hoverLabelTextLayer.alignmentMode = .center
            hoverLabelTextLayer.truncationMode = .end
            hoverLabelTextLayer.foregroundColor = NSColor(calibratedWhite: 0.08, alpha: 1).cgColor
            hoverLabelLayer.addSublayer(hoverLabelTextLayer)
            layer?.addSublayer(hoverLabelLayer)
        }

        required init?(coder: NSCoder) { nil }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let mouseDownMonitor {
                NSEvent.removeMonitor(mouseDownMonitor)
                self.mouseDownMonitor = nil
            }
            if let mouseUpMonitor {
                NSEvent.removeMonitor(mouseUpMonitor)
                self.mouseUpMonitor = nil
            }
            if let globalMouseUpMonitor {
                NSEvent.removeMonitor(globalMouseUpMonitor)
                self.globalMouseUpMonitor = nil
            }
            if window == nil { finishPress() }
            guard window != nil else { return }
            mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self, event.window === self.window else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                if let id = self.favoriteItemID(at: point, utilitiesOnly: false) {
                    self.beginPress(for: id)
                }
                return event
            }
            mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
                self?.finishPress()
                return event
            }
            globalMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
                DispatchQueue.main.async { self?.finishPress() }
            }
        }

        func beginPress(for id: String) {
            guard let index = favoriteIDs.firstIndex(of: id),
                  id != "utility:separator" else { return }
            finishPress()
            pressedFavoriteID = id
            pressGeneration += 1
            let icon = iconLayers[index]
            let overlay: CALayer
            if let existing = pressOverlayLayers[id] {
                overlay = existing
            } else {
                overlay = CALayer()
                overlay.backgroundColor = NSColor.black.cgColor
                overlay.opacity = 0
                let mask = CALayer()
                mask.contentsGravity = .resizeAspect
                overlay.mask = mask
                icon.addSublayer(overlay)
                pressOverlayLayers[id] = overlay
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            overlay.frame = icon.bounds
            overlay.mask?.frame = overlay.bounds
            overlay.mask?.contents = icon.contents
            CATransaction.commit()

            overlay.removeAllAnimations()
            overlay.opacity = 0.42
        }

        private func finishPress() {
            guard let id = pressedFavoriteID else { return }
            pressedFavoriteID = nil
            pressGeneration += 1
            let generation = pressGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, self.pressGeneration == generation,
                      let overlay = self.pressOverlayLayers[id] else { return }
                CATransaction.begin()
                CATransaction.setAnimationDuration(0.14)
                overlay.opacity = 0
                CATransaction.commit()
            }
        }

        func utilityItemID(at point: CGPoint) -> String? {
            favoriteItemID(at: point, utilitiesOnly: true)
        }

        func itemID(at point: CGPoint) -> String? {
            favoriteItemID(at: point, utilitiesOnly: false)
        }

        func iconCenter(for id: String) -> CGPoint? {
            guard let index = favoriteIDs.firstIndex(of: id),
                  iconLayers.indices.contains(index) else { return nil }
            let icon = iconLayers[index].presentation() ?? iconLayers[index]
            return CGPoint(x: icon.position.x,
                           y: icon.position.y + icon.bounds.height * icon.transform.m22 / 2)
        }

        private var hiddenDraggedItemID: String?

        func hideDraggedItem(_ id: String?) {
            hiddenDraggedItemID = id
            updateLayers(animated: false)
        }

        private func favoriteItemID(at point: CGPoint, utilitiesOnly: Bool) -> String? {
            for index in iconLayers.indices.reversed() {
                let id = favoriteIDs[index]
                guard id != "utility:separator" else { continue }
                if utilitiesOnly,
                   id != "utility:trash" && !id.hasPrefix("utility:folder:") { continue }
                let icon = iconLayers[index].presentation() ?? iconLayers[index]
                let halfWidth = max(15 * sizeScale, icon.bounds.width * icon.transform.m11 / 2)
                let halfHeight = max(15 * sizeScale, icon.bounds.height * icon.transform.m22 / 2)
                let centerY = icon.position.y + icon.bounds.height * icon.transform.m22 / 2
                if abs(point.x - icon.position.x) <= halfWidth,
                   abs(point.y - centerY) <= halfHeight {
                    return id
                }
            }
            return nil
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            updateIndicatorColors()
        }

        func configure(
            items: [FavoriteShelfItem],
            runningApplicationIDs: Set<String>,
            badgeLabels: [String: String],
            sizeScale: CGFloat,
            peakScale: CGFloat,
            dragOffsets: [CGFloat],
            dragSlotShifts: [Int],
            draggedFavoriteID: String?,
            isSettlingDrag: Bool,
            showsHoverLabel: Bool
        ) {
            let ids = items.map(\.id)
            let names = items.map(\.name)
            let nextTrashIsFull = items.compactMap(\.trashIsFull).first
            let trashChanged = trashIsFull != nextTrashIsFull
            let favoritesChanged = ids != favoriteIDs
            let namesChanged = names != favoriteNames
            let indicatorsChanged = favoritesChanged || self.runningApplicationIDs != runningApplicationIDs
            let badgesChanged = favoritesChanged || self.badgeLabels != badgeLabels
            let sizeChanged = self.sizeScale != sizeScale || self.peakScale != peakScale
            if favoritesChanged {
                stopEntryAnimation()
                stopSlotShiftAnimation()
                let oldIcons = Dictionary(uniqueKeysWithValues: zip(favoriteIDs, iconLayers))
                let oldIndicators = Dictionary(uniqueKeysWithValues: zip(favoriteIDs, indicatorLayers))
                let oldBadges = Dictionary(uniqueKeysWithValues: zip(favoriteIDs, badgeLayers))
                let retainedIDs = Set(ids)
                for id in favoriteIDs where !retainedIDs.contains(id) {
                    oldIcons[id]?.removeFromSuperlayer()
                    oldIndicators[id]?.removeFromSuperlayer()
                    oldBadges[id]?.removeFromSuperlayer()
                    pressOverlayLayers[id] = nil
                }
                iconLayers = items.map { item in
                    if let existing = oldIcons[item.id] { return existing }
                    let icon = CALayer()
                    if item.isSeparator {
                        icon.backgroundColor = NSColor(calibratedWhite: 0.82, alpha: 0.55).cgColor
                        icon.cornerRadius = 0.5 * sizeScale
                    } else {
                        icon.contents = item.icon
                            .cgImage(forProposedRect: nil, context: nil, hints: nil)
                    }
                    icon.contentsGravity = .resizeAspect
                    icon.magnificationFilter = .linear
                    icon.anchorPoint = CGPoint(x: 0.5, y: 0)
                    icon.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
                    layer?.addSublayer(icon)
                    return icon
                }
                indicatorLayers = items.map { item in
                    if let existing = oldIndicators[item.id] { return existing }
                    let indicator = CALayer()
                    indicator.zPosition = 0.5
                    layer?.addSublayer(indicator)
                    return indicator
                }
                badgeLayers = items.map { item in
                    if let existing = oldBadges[item.id] { return existing }
                    let badge = CALayer()
                    badge.zPosition = 22
                    badge.backgroundColor = NSColor.systemRed.cgColor
                    badge.masksToBounds = true
                    badge.opacity = 0
                    let text = CATextLayer()
                    text.alignmentMode = .center
                    text.foregroundColor = NSColor.white.cgColor
                    badge.addSublayer(text)
                    layer?.addSublayer(badge)
                    return badge
                }
                favoriteIDs = ids
                slotShiftStarts = Array(repeating: 0, count: ids.count)
                slotShiftTargets = slotShiftStarts
            }
            if trashChanged,
               let index = items.firstIndex(where: { $0.trashIsFull != nil }) {
                iconLayers[index].contents = items[index].icon
                    .cgImage(forProposedRect: nil, context: nil, hints: nil)
            }
            trashIsFull = nextTrashIsFull
            favoriteNames = names
            let dragOffsetsChanged = self.dragOffsets != dragOffsets
            let nextSlotShifts = dragSlotShifts.map(CGFloat.init)
            let slotShiftsChanged = nextSlotShifts != slotShiftTargets
            guard indicatorsChanged || badgesChanged || namesChanged || trashChanged
                    || sizeChanged || dragOffsetsChanged || slotShiftsChanged
                    || self.draggedFavoriteID != draggedFavoriteID
                    || self.isSettlingDrag != isSettlingDrag
                    || self.showsHoverLabel != showsHoverLabel else { return }
            self.runningApplicationIDs = runningApplicationIDs
            self.badgeLabels = badgeLabels
            self.sizeScale = sizeScale
            self.peakScale = peakScale
            self.dragOffsets = dragOffsets
            if slotShiftsChanged { animateSlotShifts(to: nextSlotShifts) }
            self.draggedFavoriteID = draggedFavoriteID
            self.isSettlingDrag = isSettlingDrag
            self.showsHoverLabel = showsHoverLabel
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let iconSize = FavoriteMagnificationLayout.iconSize * sizeScale
            for (index, icon) in iconLayers.enumerated() {
                let isSeparator = items[index].isSeparator
                icon.bounds = CGRect(
                    x: 0, y: 0,
                    width: isSeparator ? 1 * sizeScale : iconSize,
                    height: isSeparator ? 22 * sizeScale : iconSize
                )
                if isSeparator { icon.cornerRadius = 0.5 * sizeScale }
            }
            for indicator in indicatorLayers {
                let diameter = FavoriteMagnificationLayout.indicatorDiameter * sizeScale
                indicator.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
                indicator.cornerRadius = diameter / 2
            }
            if badgesChanged || sizeChanged {
                for (index, badge) in badgeLayers.enumerated() {
                    configureBadge(badge, label: badgeLabels[ids[index]], sizeScale: sizeScale)
                }
            }
            hoverLabelTextLayer.contentsScale = window?.backingScaleFactor
                ?? NSScreen.main?.backingScaleFactor ?? 2
            if indicatorsChanged { updateIndicatorColors() }
            CATransaction.commit()
            updateLayers(animated: false, animateReorder: favoritesChanged)
        }

        private func slotShiftProgress(at time: CFTimeInterval) -> CGFloat {
            guard let slotShiftStartedAt else { return 1 }
            let fraction = min(1, max(0, CGFloat((time - slotShiftStartedAt) / 0.16)))
            return 1 - pow(1 - fraction, 3)
        }

        private func currentSlotShift(at index: Int, time: CFTimeInterval) -> CGFloat {
            guard slotShiftTargets.indices.contains(index) else { return 0 }
            let progress = slotShiftProgress(at: time)
            return slotShiftStarts[index]
                + (slotShiftTargets[index] - slotShiftStarts[index]) * progress
        }

        private func animateSlotShifts(to targets: [CGFloat]) {
            let now = CACurrentMediaTime()
            slotShiftStarts = targets.indices.map { currentSlotShift(at: $0, time: now) }
            slotShiftTargets = targets
            slotShiftStartedAt = now
            if slotShiftTimer == nil {
                let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                    guard let self else { return }
                    if self.slotShiftProgress(at: CACurrentMediaTime()) >= 1 {
                        self.stopSlotShiftAnimation()
                    }
                    self.updateLayers(animated: false)
                }
                slotShiftTimer = timer
                RunLoop.main.add(timer, forMode: .common)
            }
        }

        private func stopSlotShiftAnimation() {
            slotShiftTimer?.invalidate()
            slotShiftTimer = nil
            slotShiftStartedAt = nil
            slotShiftStarts = slotShiftTargets
        }

        private func updateIndicatorColors() {
            for indicator in indicatorLayers {
                indicator.backgroundColor = NSColor(calibratedWhite: 0.82, alpha: 0.96).cgColor
            }
        }

        private func configureBadge(_ badge: CALayer, label: String?, sizeScale: CGFloat) {
            guard let label, let text = badge.sublayers?.first as? CATextLayer else { return }
            let height = 13 * sizeScale
            let width = (label.count == 1 ? 13 : CGFloat(label.count) * 7 + 6) * sizeScale
            badge.bounds = CGRect(x: 0, y: 0, width: width, height: height)
            badge.cornerRadius = height / 2
            text.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
            text.font = NSFont.systemFont(ofSize: 9 * sizeScale, weight: .semibold)
            text.fontSize = 9 * sizeScale
            text.string = label
            text.frame = CGRect(x: 1, y: 1.5 * sizeScale,
                                width: width - 2, height: height - 2 * sizeScale)
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
                (iconLayers + indicatorLayers + badgeLayers).forEach { $0.removeAllAnimations() }
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

        private func animateReorderPosition(_ target: CGPoint, on layer: CALayer) {
            guard layer.position != target else { return }
            let current = layer.presentation()?.position ?? layer.position
            layer.position = target
            let movement = CABasicAnimation(keyPath: "position")
            movement.fromValue = current
            movement.toValue = target
            movement.duration = 0.18
            movement.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(movement, forKey: "favorite-reorder-position")
        }

        private func updateLayers(animated: Bool, animateReorder: Bool = false) {
            let layout = FavoriteMagnificationLayout(
                count: iconLayers.count,
                pointerX: pointerX,
                sizeScale: sizeScale,
                separatorIndices: Set(favoriteIDs.enumerated().compactMap { index, id in
                    id == "utility:separator" ? index : nil
                }),
                peakScale: peakScale
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
            let hoveredIndex: Int? = pointerX.flatMap { x in
                guard showsHoverLabel, !favoriteNames.isEmpty else { return nil }
                if let draggedFavoriteID {
                    return favoriteIDs.firstIndex(of: draggedFavoriteID)
                }
                return FavoriteMagnificationLayout.hoveredItemIndex(
                    pointerX: x, count: favoriteNames.count, sizeScale: sizeScale,
                    separatorIndices: Set(favoriteIDs.enumerated().compactMap {
                        $0.element == "utility:separator" ? $0.offset : nil
                    }),
                    excludedIndices: Set(favoriteNames.enumerated().compactMap {
                        $0.element.isEmpty ? $0.offset : nil
                    })
                )
            }
            var hoveredIconTop: CGPoint?
            let slotTime = CACurrentMediaTime()
            for (index, icon) in iconLayers.enumerated() {
                let favoriteID = favoriteIDs[index]
                let isDragHidden = favoriteID == hiddenDraggedItemID
                icon.opacity = isDragHidden ? 0 : 1
                let isDragged = favoriteID == draggedFavoriteID && pointerX != nil
                let scale = isDragged ? peakScale : layout.scales[index]
                let isRunning = runningApplicationIDs.contains(favoriteID)
                let slotShift = currentSlotShift(at: index, time: slotTime)
                let slotDestination = index + (slotShift < 0 ? -1 : 1)
                let slotOffset = layout.reorderPreviewOffset(from: index,
                    to: slotDestination, sizeScale: sizeScale) * abs(slotShift)
                let geometry = layout.visualGeometry(
                    at: index,
                    sizeScale: sizeScale,
                    dragOffset: favoriteID == draggedFavoriteID
                        ? (dragOffsets.indices.contains(index) ? dragOffsets[index] : 0)
                        : slotOffset,
                    isNoWindow: true
                )
                let isSeparator = favoriteID == "utility:separator"
                let targetIconPosition = CGPoint(
                    x: geometry.centerX,
                    y: isSeparator ? 7 * sizeScale
                        : isDragged ? 6 * sizeScale
                            - FavoriteMagnificationLayout.lift(for: scale) * sizeScale
                        : geometry.iconBottomY
                )
                // The dragged icon already has a floating preview at its live
                // pointer position. Replaying its entry from the original slot
                // makes it visibly jump when the pointer returns to the shelf.
                let entry = favoriteID != draggedFavoriteID && entryStates.indices.contains(index)
                    ? entryStates[index] : nil
                let displayedScale = entry.map {
                    $0.iconScale + (scale - $0.iconScale) * entryProgress
                } ?? scale
                let displayedIconPosition = entry.map {
                    CGPoint(
                        x: $0.iconPosition.x + (targetIconPosition.x - $0.iconPosition.x) * entryProgress,
                        y: $0.iconPosition.y + (targetIconPosition.y - $0.iconPosition.y) * entryProgress
                    )
                } ?? targetIconPosition
                let animatePosition = animateReorder
                    && (favoriteID != draggedFavoriteID || isSettlingDrag)
                if animatePosition {
                    animateReorderPosition(displayedIconPosition, on: icon)
                } else {
                    icon.position = displayedIconPosition
                }
                if isSeparator {
                    icon.transform = CATransform3DIdentity
                    icon.zPosition = 0
                    indicatorLayers[index].opacity = 0
                    badgeLayers[index].opacity = 0
                    continue
                }
                icon.transform = CATransform3DMakeScale(displayedScale, displayedScale, 1)
                icon.zPosition = favoriteID == draggedFavoriteID ? 20 : displayedScale
                if index == hoveredIndex {
                    hoveredIconTop = CGPoint(
                        x: displayedIconPosition.x,
                        y: displayedIconPosition.y
                            + FavoriteMagnificationLayout.iconSize * sizeScale * displayedScale
                    )
                }

                let indicator = indicatorLayers[index]
                let targetIndicatorPosition = CGPoint(
                    x: geometry.centerX,
                    y: geometry.indicatorCenterY
                )
                let indicatorScale = 1 + (scale - 1) * 0.5
                let displayedIndicatorPosition = entry.map {
                    CGPoint(
                        x: $0.indicatorPosition.x + (targetIndicatorPosition.x - $0.indicatorPosition.x) * entryProgress,
                        y: $0.indicatorPosition.y + (targetIndicatorPosition.y - $0.indicatorPosition.y) * entryProgress
                    )
                } ?? targetIndicatorPosition
                if animatePosition {
                    animateReorderPosition(displayedIndicatorPosition, on: indicator)
                } else {
                    indicator.position = displayedIndicatorPosition
                }
                let displayedIndicatorScale = entry.map {
                    $0.indicatorScale + (indicatorScale - $0.indicatorScale) * entryProgress
                } ?? indicatorScale
                indicator.transform = CATransform3DMakeScale(displayedIndicatorScale, displayedIndicatorScale, 1)
                indicator.opacity = isRunning && !isDragHidden ? 1 : 0

                let badge = badgeLayers[index]
                let badgePosition = CGPoint(
                    x: displayedIconPosition.x
                        + FavoriteMagnificationLayout.iconSize * sizeScale * displayedScale * 0.38,
                    y: displayedIconPosition.y
                        + FavoriteMagnificationLayout.iconSize * sizeScale * displayedScale * 0.90
                )
                if animatePosition {
                    animateReorderPosition(badgePosition, on: badge)
                } else {
                    badge.position = badgePosition
                }
                let badgeScale = 1 + (displayedScale - 1) * 0.55
                badge.transform = CATransform3DMakeScale(badgeScale, badgeScale, 1)
                badge.opacity = badgeLabels[favoriteID] == nil || isDragHidden ? 0 : 1
            }
            updateHoverLabel(at: hoveredIconTop, index: hoveredIndex)
            CATransaction.commit()
        }

        private func updateHoverLabel(at iconTop: CGPoint?, index: Int?) {
            guard let iconTop, let index else {
                hoverLabelLayer.opacity = 0
                return
            }
            let title = favoriteNames[index]
            let fontSize = 13 * sizeScale
            if displayedHoverLabel != title || hoverLabelTextLayer.fontSize != fontSize {
                displayedHoverLabel = title
                let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
                hoverLabelWidth = min(240 * sizeScale,
                    ceil((title as NSString).size(withAttributes: [.font: font]).width)
                        + 24 * sizeScale)
                hoverLabelTextLayer.font = font
                hoverLabelTextLayer.fontSize = fontSize
                hoverLabelTextLayer.string = title
                let totalHeight = FavoriteMagnificationLayout.hoverLabelHeight * sizeScale
                hoverLabelLayer.bounds = CGRect(x: 0, y: 0, width: hoverLabelWidth, height: totalHeight)
                hoverLabelLayer.path = Self.hoverLabelPath(
                    width: hoverLabelWidth, height: totalHeight, scale: sizeScale)
                hoverLabelTextLayer.frame = CGRect(
                    x: 9 * sizeScale, y: 10 * sizeScale,
                    width: hoverLabelWidth - 18 * sizeScale, height: 17 * sizeScale)
            }
            let viewOriginX = convert(.zero, to: window?.contentView).x
            let contentWidth = window?.contentView?.bounds.width ?? bounds.width
            let minimumX = 8 - viewOriginX + hoverLabelWidth / 2
            let maximumX = contentWidth - 8 - viewOriginX - hoverLabelWidth / 2
            let centerX = min(max(iconTop.x, minimumX), max(minimumX, maximumX))
            hoverLabelLayer.position = CGPoint(
                x: centerX,
                y: iconTop.y + 5 * sizeScale
                    + FavoriteMagnificationLayout.hoverLabelHeight * sizeScale / 2)
            hoverLabelLayer.opacity = 1
        }

        private static func hoverLabelPath(width: CGFloat, height: CGFloat, scale: CGFloat) -> CGPath {
            let tailHeight = 6 * scale
            let radius = 12 * scale
            let center = width / 2
            let path = CGMutablePath()
            path.move(to: CGPoint(x: radius, y: tailHeight))
            path.addLine(to: CGPoint(x: center - 6 * scale, y: tailHeight))
            path.addLine(to: CGPoint(x: center, y: 0))
            path.addLine(to: CGPoint(x: center + 6 * scale, y: tailHeight))
            path.addLine(to: CGPoint(x: width - radius, y: tailHeight))
            path.addQuadCurve(to: CGPoint(x: width, y: tailHeight + radius),
                              control: CGPoint(x: width, y: tailHeight))
            path.addLine(to: CGPoint(x: width, y: height - radius))
            path.addQuadCurve(to: CGPoint(x: width - radius, y: height),
                              control: CGPoint(x: width, y: height))
            path.addLine(to: CGPoint(x: radius, y: height))
            path.addQuadCurve(to: CGPoint(x: 0, y: height - radius),
                              control: CGPoint(x: 0, y: height))
            path.addLine(to: CGPoint(x: 0, y: tailHeight + radius))
            path.addQuadCurve(to: CGPoint(x: radius, y: tailHeight),
                              control: CGPoint(x: 0, y: tailHeight))
            path.closeSubpath()
            return path
        }
    }
}

private struct FavoriteShelfButton: View {
    let item: FavoriteShelfItem
    let isRunning: Bool
    let badgeLabel: String?
    let shortcutLabel: String?
    let sizeScale: CGFloat
    let onOpen: () -> Void

    var body: some View {
        button
    }

    private var button: some View {
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
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(item.isRemovable
            ? "点击打开；长按或右键显示菜单；拖动可调整收藏顺序，拖出停留 0.5 秒后松手移除收藏"
            : "点击打开；长按或右键显示菜单")
    }

    private var accessibilityLabel: String {
        switch item {
        case .app(let app): return "收藏：\(app.applicationName)"
        case .separator: return "分隔线"
        case .trash(let isFull): return isFull ? "打开废纸篓，非空" : "打开废纸篓，空"
        case .folder(let folder): return "打开收藏文件夹：\(folder.name)"
        case .insertionGap: return ""
        }
    }

    private var accessibilityValue: String {
        guard item.app != nil else { return "" }
        return [isRunning ? "正在运行" : "未运行", badgeLabel.map { "\($0) 条未读" }]
            .compactMap { $0 }.joined(separator: "，")
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
