import AppKit
import SwiftUI

struct FavoriteShelfMenuAction {
    let title: String?
    let isEnabled: Bool
    let perform: (() -> Void)?

    init(title: String?, isEnabled: Bool = true, perform: (() -> Void)?) {
        self.title = title
        self.isEnabled = isEnabled
        self.perform = perform
    }

    static let separator = FavoriteShelfMenuAction(title: nil, perform: nil)
}

/// Owns the mouse capture so dragging continues above and outside the panel.
struct FavoriteShelfInteractionView: NSViewRepresentable {
    let shelfInset: CGFloat
    let shelfWidth: CGFloat
    let shelfHeight: CGFloat
    let previewSize: CGFloat
    let onLocationChange: (CGPoint?) -> Void
    let itemAt: (CGPoint) -> String?
    let iconCenterForItem: (String) -> CGPoint?
    let iconForItem: (String) -> NSImage?
    let canDragItem: (String) -> Bool
    let onClick: (String) -> Void
    let onContextMenu: (String) -> [FavoriteShelfMenuAction]
    let onContextMenuVisibilityChange: (Bool) -> Void
    let onDragUpdate: (String, CGSize, Bool, CGFloat) -> Void
    let onDragEnd: (Bool) -> Void
    let onRemove: (String) -> Void
    let onDropPreview: ([URL], CGFloat) -> Bool
    let onDropURLs: ([URL], CGFloat) -> Bool
    let onExternalDragChanged: (Bool) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        configure(view)
        return view
    }

    func updateNSView(_ view: TrackingView, context: Context) { configure(view) }

    private func configure(_ view: TrackingView) {
        view.shelfInset = shelfInset
        view.shelfWidth = shelfWidth
        view.shelfHeight = shelfHeight
        view.previewSize = previewSize
        view.onLocationChange = onLocationChange
        view.itemAt = itemAt
        view.iconCenterForItem = iconCenterForItem
        view.iconForItem = iconForItem
        view.canDragItem = canDragItem
        view.onClick = onClick
        view.onContextMenu = onContextMenu
        view.onContextMenuVisibilityChange = onContextMenuVisibilityChange
        view.onDragUpdate = onDragUpdate
        view.onDragEnd = onDragEnd
        view.onRemove = onRemove
        view.onDropURLs = onDropURLs
        view.onDropPreview = onDropPreview
        view.onExternalDragChanged = onExternalDragChanged
    }

    static func dismantleNSView(_ view: TrackingView, coordinator: ()) {
        view.cancelInteraction()
    }

    final class TrackingView: NSView {
        var shelfInset: CGFloat = 0
        var shelfWidth: CGFloat = .greatestFiniteMagnitude
        var shelfHeight: CGFloat = 0
        var previewSize: CGFloat = 40
        var onLocationChange: ((CGPoint?) -> Void)?
        var itemAt: ((CGPoint) -> String?)?
        var iconCenterForItem: ((String) -> CGPoint?)?
        var iconForItem: ((String) -> NSImage?)?
        var canDragItem: ((String) -> Bool)?
        var onClick: ((String) -> Void)?
        var onContextMenu: ((String) -> [FavoriteShelfMenuAction])?
        var onContextMenuVisibilityChange: ((Bool) -> Void)?
        var onDragUpdate: ((String, CGSize, Bool, CGFloat) -> Void)?
        var onDragEnd: ((Bool) -> Void)?
        var onRemove: ((String) -> Void)?
        var onDropPreview: (([URL], CGFloat) -> Bool)?
        var onDropURLs: (([URL], CGFloat) -> Bool)?
        var onExternalDragChanged: ((Bool) -> Void)?
        private var externalDragActive = false
        private var hoverArea: NSTrackingArea?
        private var pressedID: String?
        private var startPoint = CGPoint.zero
        private var grabOffset = CGPoint.zero
        private var lastDragOutside: Bool?
        private var dragging = false
        private var removalState = FavoriteDragRemovalState()
        private var removalTimer: Timer?
        private var longPressTimer: Timer?
        private var captureHeartbeat: Timer?
        private var preview: NSPanel?
        private var escapeMonitor: Any?
        private var pendingLocation: CGPoint?
        private var updateScheduled = false
        private var pendingDrag: (id: String, translation: CGSize, outside: Bool, x: CGFloat)?
        private var dragUpdateScheduled = false
        private var dragUpdateGeneration = 0
        private var contextPanel: DockContextMenuPanel?
        private var contextDismissMonitor: Any?
        private var contextGlobalDismissMonitor: Any?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            registerForDraggedTypes([.fileURL])
        }

        required init?(coder: NSCoder) { nil }

        private var shelfRect: NSRect {
            NSRect(x: shelfInset, y: 0, width: min(shelfWidth, max(0, bounds.width - 2 * shelfInset)), height: shelfHeight)
        }

        private var dragRect: NSRect {
            NSRect(x: shelfInset, y: 0, width: max(0, bounds.width - 2 * shelfInset), height: shelfHeight)
        }

        private func isOutside(_ point: CGPoint) -> Bool {
            !dragRect.insetBy(dx: -12, dy: -12).contains(point)
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            let location = convert(point, from: superview)
            guard bounds.contains(location), shelfRect.contains(location) || itemAt?(location) != nil else { return nil }
            return self
        }

        override func updateTrackingAreas() {
            if let hoverArea { removeTrackingArea(hoverArea) }
            let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved,
                .activeAlways, .enabledDuringMouseDrag, .inVisibleRect], owner: self, userInfo: nil)
            addTrackingArea(area)
            hoverArea = area
            super.updateTrackingAreas()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor); self.escapeMonitor = nil }
            guard window != nil else { cancelInteraction(); return }
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.dragging, event.keyCode == 53 else { return event }
                self.cancelInteraction()
                return nil
            }
        }

        override func mouseDown(with event: NSEvent) {
            guard contextPanel == nil else { return }
            startPoint = convert(event.locationInWindow, from: nil)
            pressedID = itemAt?(startPoint)
            longPressTimer?.invalidate()
            longPressTimer = nil
            if let pressedID, let iconCenter = iconCenterForItem?(pressedID) {
                grabOffset = CGPoint(x: startPoint.x - iconCenter.x,
                                     y: startPoint.y - iconCenter.y)
            } else {
                grabOffset = .zero
            }
            if let id = pressedID {
                let timer = Timer(timeInterval: 0.55, repeats: false) { [weak self] _ in
                    guard let self, self.pressedID == id, !self.dragging,
                          NSEvent.pressedMouseButtons & 1 != 0,
                          let window = self.window else { return }
                    let point = self.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
                    guard hypot(point.x - self.startPoint.x, point.y - self.startPoint.y) < 8,
                          self.itemAt?(point) == id else { return }
                    self.pressedID = nil
                    self.longPressTimer = nil
                    self.showContextMenu(for: id, event: nil)
                }
                longPressTimer = timer
                RunLoop.main.add(timer, forMode: .common)
            }
        }

        override func mouseDragged(with event: NSEvent) {
            let location = convert(event.locationInWindow, from: nil)
            if hypot(location.x - startPoint.x, location.y - startPoint.y) >= 8 {
                longPressTimer?.invalidate()
                longPressTimer = nil
            }
            guard let id = pressedID, canDragItem?(id) == true,
                  !event.modifierFlags.contains(.option) else { return }
            let translation = CGSize(width: location.x - startPoint.x, height: location.y - startPoint.y)
            guard dragging || hypot(translation.width, translation.height) >= 12 else { return }
            let justStarted = !dragging
            if justStarted {
                dragging = true
                let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
                    guard let self, self.dragging else { return }
                    // Renew the controller's refresh pause even when the mouse stops in the shelf.
                    self.onExternalDragChanged?(true)
                }
                captureHeartbeat = timer
                RunLoop.main.add(timer, forMode: .common)
            }
            let outside = isOutside(location)
            if justStarted || lastDragOutside != outside {
                // Entering or leaving the shelf must update the real icon before
                // the floating preview appears or disappears.
                dragUpdateGeneration += 1
                pendingDrag = nil
                dragUpdateScheduled = false
                onDragUpdate?(id, translation, outside, location.x)
            } else {
                scheduleDragUpdate(id: id, translation: translation,
                    outside: outside, x: location.x)
            }
            lastDragOutside = outside
            updateRemoval(outside: outside, id: id)
            updatePreview(outside: outside, id: id)
        }

        private func scheduleDragUpdate(id: String, translation: CGSize,
                                        outside: Bool, x: CGFloat) {
            pendingDrag = (id, translation, outside, x)
            guard !dragUpdateScheduled else { return }
            dragUpdateScheduled = true
            let generation = dragUpdateGeneration
            let framesPerSecond = min(120, max(60,
                window?.screen?.maximumFramesPerSecond ?? 60))
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / Double(framesPerSecond)) { [weak self] in
                guard let self, self.dragUpdateGeneration == generation else { return }
                self.dragUpdateScheduled = false
                guard let update = self.pendingDrag else { return }
                self.pendingDrag = nil
                self.onDragUpdate?(update.id, update.translation,
                    update.outside, update.x)
            }
        }

        override func mouseUp(with event: NSEvent) {
            longPressTimer?.invalidate()
            longPressTimer = nil
            let id = pressedID
            let wasDragging = dragging
            let location = convert(event.locationInWindow, from: nil)
            let outside = isOutside(location)
            if wasDragging, !outside, let id {
                let translation = CGSize(width: location.x - startPoint.x,
                                         height: location.y - startPoint.y)
                onDragUpdate?(id, translation, false, location.x)
            }
            let shouldRemove = wasDragging && removalState.shouldRemove(onReleaseOutside: outside,
                now: ProcessInfo.processInfo.systemUptime)
            resetCapture()
            if shouldRemove, let id {
                onRemove?(id)
            } else if wasDragging {
                onDragEnd?(outside)
            } else if let id {
                let stayedNearPress = hypot(location.x - startPoint.x,
                                            location.y - startPoint.y) < 8
                if itemAt?(location) == id || stayedNearPress { onClick?(id) }
            }
        }

        override func rightMouseDown(with event: NSEvent) {
            guard contextPanel == nil else { return }
            longPressTimer?.invalidate()
            longPressTimer = nil
            guard !dragging, let id = itemAt?(convert(event.locationInWindow, from: nil)) else { return }
            showContextMenu(for: id, event: event)
        }

        private func showContextMenu(for id: String, event: NSEvent?) {
            guard let actions = onContextMenu?(id), !actions.isEmpty else { return }
            guard let window else { return }
            closeContextMenu()
            let pointInWindow = event?.locationInWindow
                ?? window.convertPoint(fromScreen: NSEvent.mouseLocation)
            let iconCenterX = iconCenterForItem?(id).map { convert($0, to: nil).x }
                ?? pointInWindow.x
            let screenPoint = window.convertPoint(toScreen: CGPoint(
                x: iconCenterX, y: pointInWindow.y
            ))
            let menuWidth = DockStyleContextMenu.width(for: actions)
            let menuHeight = DockStyleContextMenu.height(for: actions) + 24
            let menuSize = NSSize(width: menuWidth, height: menuHeight)
            let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame ?? window.frame
            let originX = min(max(screenPoint.x - menuSize.width / 2, visibleFrame.minX + 8),
                              visibleFrame.maxX - menuSize.width - 8)
            let originY = min(screenPoint.y + min(previewSize, 44) / 2 + 4,
                              visibleFrame.maxY - menuSize.height - 8)
            let arrowX = min(max(screenPoint.x - originX, 20), menuSize.width - 20)
            let panel = DockContextMenuPanel(
                contentRect: NSRect(origin: CGPoint(x: originX, y: originY), size: menuSize),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = .popUpMenu
            panel.acceptsMouseMovedEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let hoverState = DockMenuHoverState()
            panel.onPointerEvent = { point in
                guard point.x >= 5, point.x <= menuWidth - 5 else {
                    hoverState.setIndex(nil)
                    return
                }
                var distanceFromTop = menuHeight - point.y - 10
                for (index, action) in actions.enumerated() {
                    let rowHeight: CGFloat = action.title == nil ? 11 : 29
                    if distanceFromTop >= 0, distanceFromTop < rowHeight {
                        hoverState.setIndex(action.title == nil || !action.isEnabled ? nil : index)
                        return
                    }
                    distanceFromTop -= rowHeight
                }
                hoverState.setIndex(nil)
            }
            let hosting = NSHostingView(rootView: DockStyleContextBubble(
                actions: actions, arrowX: arrowX, menuWidth: menuWidth,
                hoverState: hoverState
            ) { [weak self] action in
                self?.closeContextMenu()
                action()
            })
            hosting.frame = NSRect(origin: .zero, size: menuSize)
            hosting.appearance = NSAppearance(named: .aqua)
            panel.contentView = hosting
            contextPanel = panel
            onContextMenuVisibilityChange?(true)
            panel.makeKeyAndOrderFront(nil)
            contextDismissMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .keyDown]
            ) { [weak self] event in
                guard let self else { return event }
                if event.type == .keyDown && event.keyCode == 53 {
                    self.closeContextMenu()
                    return nil
                }
                if event.type != .keyDown, event.window != self.contextPanel {
                    self.closeContextMenu()
                    return nil
                }
                return event
            }
            contextGlobalDismissMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] _ in
                guard let self else { return }
                let location = NSEvent.mouseLocation
                if self.window?.frame.contains(location) == true
                    || self.contextPanel?.frame.contains(location) == true { return }
                self.closeContextMenu()
            }
        }

        private func closeContextMenu() {
            let wasOpen = contextPanel != nil
            if let contextDismissMonitor { NSEvent.removeMonitor(contextDismissMonitor) }
            if let contextGlobalDismissMonitor { NSEvent.removeMonitor(contextGlobalDismissMonitor) }
            contextDismissMonitor = nil
            contextGlobalDismissMonitor = nil
            contextPanel?.close()
            contextPanel = nil
            if wasOpen {
                pendingLocation = nil
                onContextMenuVisibilityChange?(false)
                onLocationChange?(nil)
            }
        }

        private func updateRemoval(outside: Bool, id: String) {
            removalState.update(isOutside: outside, now: ProcessInfo.processInfo.systemUptime)
            if !outside {
                removalTimer?.invalidate()
                removalTimer = nil
                return
            }
            guard removalTimer == nil else { return }
            let timer = Timer(timeInterval: FavoriteDragRemovalState.delay, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.removalTimer = nil
                guard self.dragging, self.pressedID == id, NSEvent.pressedMouseButtons & 1 != 0,
                      self.removalState.isReady(now: ProcessInfo.processInfo.systemUptime),
                      let window = self.window else { return }
                let point = self.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
                guard self.isOutside(point) else {
                    self.removalState.cancel()
                    self.preview?.orderOut(nil)
                    self.onDragUpdate?(id, CGSize(width: point.x - self.startPoint.x,
                                                  height: point.y - self.startPoint.y), false, point.x)
                    return
                }
                // Only arm the action. The item remains in SettingsStore until mouse-up.
                self.updatePreview(outside: true, id: id)
            }
            removalTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }

        private func updatePreview(outside: Bool, id: String) {
            guard outside else { preview?.orderOut(nil); return }
            if preview == nil {
                let content = FavoriteDragPreviewView(icon: iconForItem?(id), iconSize: previewSize)
                let panel = NSPanel(contentRect: content.bounds,
                    styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.isOpaque = false
                panel.backgroundColor = .clear
                panel.hasShadow = false
                panel.ignoresMouseEvents = true
                panel.level = .popUpMenu
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                panel.contentView = content
                preview = panel
            }
            (preview?.contentView as? FavoriteDragPreviewView)?.setReady(
                removalState.isReady(now: ProcessInfo.processInfo.systemUptime))
            let mouse = NSEvent.mouseLocation
            preview?.setFrameOrigin(NSPoint(x: mouse.x - grabOffset.x - 70,
                                            y: mouse.y - grabOffset.y - previewSize / 2 - 8))
            preview?.orderFrontRegardless()
        }

        private func resetCapture() {
            dragUpdateGeneration += 1
            pendingDrag = nil
            dragUpdateScheduled = false
            captureHeartbeat?.invalidate()
            captureHeartbeat = nil
            removalTimer?.invalidate()
            removalTimer = nil
            longPressTimer?.invalidate()
            longPressTimer = nil
            removalState.cancel()
            preview?.orderOut(nil)
            preview = nil
            pressedID = nil
            dragging = false
            lastDragOutside = nil
            grabOffset = .zero
        }

        func cancelInteraction() {
            let wasDragging = dragging
            closeContextMenu()
            resetCapture()
            if wasDragging { onDragEnd?(true) }
            endExternalDrag()
            onLocationChange?(nil)
            if window == nil, let escapeMonitor {
                NSEvent.removeMonitor(escapeMonitor)
                self.escapeMonitor = nil
            }
        }

        override func mouseEntered(with event: NSEvent) { updateLocation(event) }
        override func mouseMoved(with event: NSEvent) { updateLocation(event) }
        override func mouseExited(with event: NSEvent) {
            guard contextPanel == nil else { return }
            pendingLocation = nil
            onLocationChange?(nil)
        }

        private func updateLocation(_ event: NSEvent) {
            guard !dragging, contextPanel == nil else { return }
            let location = convert(event.locationInWindow, from: nil)
            // Animation headroom is not a hover target. Continue only over the shelf
            // or an actual magnified icon extending past its original slots.
            let isOverShelf = bounds.contains(location)
                && (shelfRect.contains(location) || itemAt?(location) != nil)
            pendingLocation = isOverShelf ? location : nil
            guard !updateScheduled else { return }
            updateScheduled = true
            let fps = max(60, window?.screen?.maximumFramesPerSecond ?? 60)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1 / Double(min(fps * 2, 240))) { [weak self] in
                guard let self else { return }
                self.updateScheduled = false
                if !self.dragging, self.contextPanel == nil {
                    self.onLocationChange?(self.pendingLocation)
                }
            }
        }

        private func droppedURLs(_ sender: NSDraggingInfo) -> [URL] {
            let objects = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
            return FavoriteShelfDrop.supportedURLs(objects)
        }

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            onLocationChange?(nil)
            return draggingUpdated(sender)
        }

        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
            let location = convert(sender.draggingLocation, from: nil)
            guard !dragging, shelfRect.contains(location),
                  !droppedURLs(sender).isEmpty,
                  onDropPreview?(droppedURLs(sender), location.x - shelfInset) == true
                else { endExternalDrag(); return [] }
            externalDragActive = true
            onExternalDragChanged?(true)
            return .copy
        }

        override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
            !draggingUpdated(sender).isEmpty
        }

        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            defer { endExternalDrag() }
            guard !draggingUpdated(sender).isEmpty else { return false }
            let x = convert(sender.draggingLocation, from: nil).x - shelfInset
            return onDropURLs?(droppedURLs(sender), x) ?? false
        }

        override func draggingExited(_ sender: NSDraggingInfo?) { endExternalDrag() }
        override func draggingEnded(_ sender: NSDraggingInfo) { endExternalDrag() }

        private func endExternalDrag() {
            guard externalDragActive else { return }
            externalDragActive = false
            onExternalDragChanged?(false)
        }

        deinit {
            closeContextMenu()
            removalTimer?.invalidate()
            captureHeartbeat?.invalidate()
            if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        }
    }
}

private final class DockContextMenuPanel: NSPanel {
    var onPointerEvent: ((NSPoint) -> Void)?
    override var canBecomeKey: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .mouseMoved, .mouseEntered, .mouseExited,
             .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
             .leftMouseDown, .rightMouseDown, .otherMouseDown:
            onPointerEvent?(event.locationInWindow)
        default: break
        }
        super.sendEvent(event)
    }
}

private final class DockMenuHoverState: ObservableObject {
    @Published var index: Int?

    func setIndex(_ next: Int?) {
        guard index != next else { return }
        index = next
    }
}

private struct DockStyleContextBubble: View {
    let actions: [FavoriteShelfMenuAction]
    let arrowX: CGFloat
    let menuWidth: CGFloat
    @ObservedObject var hoverState: DockMenuHoverState
    let onSelect: (() -> Void) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            DockStyleBubbleShape(arrowX: arrowX)
                .fill(Color(nsColor: NSColor(calibratedWhite: 0.96, alpha: 0.86)))
                .overlay {
                    DockStyleBubbleShape(arrowX: arrowX)
                        .stroke(Color.white.opacity(0.62), lineWidth: 0.8)
                }
            DockStyleContextMenu(actions: actions, menuWidth: menuWidth,
                                 hoverState: hoverState, onSelect: onSelect)
                .padding(.top, 5)
        }
        .frame(width: menuWidth, height: DockStyleContextMenu.height(for: actions) + 24)
        .compositingGroup()
        .clipShape(DockStyleBubbleShape(arrowX: arrowX))
        .shadow(color: .black.opacity(0.22), radius: 12, y: 5)
    }
}

private struct DockStyleBubbleShape: Shape {
    let arrowX: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 13
        let bottom = rect.maxY - 14
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius),
                          control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: bottom - radius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: bottom),
                          control: CGPoint(x: rect.maxX, y: bottom))
        path.addLine(to: CGPoint(x: arrowX + 11, y: bottom))
        path.addLine(to: CGPoint(x: arrowX, y: rect.maxY))
        path.addLine(to: CGPoint(x: arrowX - 11, y: bottom))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: bottom))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: bottom - radius),
                          control: CGPoint(x: rect.minX, y: bottom))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY),
                          control: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

private struct DockStyleContextMenu: View {
    let actions: [FavoriteShelfMenuAction]
    let menuWidth: CGFloat
    @ObservedObject var hoverState: DockMenuHoverState
    let onSelect: (() -> Void) -> Void

    static func width(for actions: [FavoriteShelfMenuAction]) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 13)
        let titleWidth = actions.compactMap(\.title).map {
            ($0 as NSString).size(withAttributes: [.font: font]).width
        }.max() ?? 0
        return min(220, max(148, ceil(titleWidth + 28)))
    }

    static func height(for actions: [FavoriteShelfMenuAction]) -> CGFloat {
        let rows = actions.filter { $0.title != nil }.count
        let separators = actions.count - rows
        return min(CGFloat(rows * 29 + separators * 11 + 14), 420)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(actions.indices, id: \.self) { index in
                    let action = actions[index]
                    if let title = action.title, let perform = action.perform {
                        Button { onSelect(perform) } label: {
                            Text(title)
                                .font(.system(size: 13))
                                .foregroundStyle(
                                    hoverState.index == index && action.isEnabled
                                        ? Color.white
                                        : action.isEnabled ? Color.primary : Color.secondary
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 7)
                                .frame(height: 29)
                                .contentShape(Rectangle())
                                .background {
                                    if hoverState.index == index && action.isEnabled {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.accentColor.opacity(0.85))
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .dockMenuFocusAppearance()
                        .disabled(!action.isEnabled)
                        .onHover { inside in
                            if inside { hoverState.setIndex(index) }
                            else if hoverState.index == index { hoverState.setIndex(nil) }
                        }
                    } else if index > 0 && index < actions.count - 1 {
                        Divider().padding(.horizontal, 12).padding(.vertical, 5)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(5)
        }
        .frame(width: menuWidth - 10, height: Self.height(for: actions))
    }
}

private extension View {
    @ViewBuilder func dockMenuFocusAppearance() -> some View {
        if #available(macOS 14, *) {
            focusEffectDisabled()
        } else {
            self
        }
    }
}
