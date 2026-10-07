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
    let previewSize: CGFloat
    let onLocationChange: (CGPoint?) -> Void
    let itemAt: (CGPoint) -> String?
    let iconCenterForItem: (String) -> CGPoint?
    let iconForItem: (String) -> NSImage?
    let canDragItem: (String) -> Bool
    let onClick: (String) -> Void
    let onContextMenu: (String) -> [FavoriteShelfMenuAction]
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
        view.previewSize = previewSize
        view.onLocationChange = onLocationChange
        view.itemAt = itemAt
        view.iconCenterForItem = iconCenterForItem
        view.iconForItem = iconForItem
        view.canDragItem = canDragItem
        view.onClick = onClick
        view.onContextMenu = onContextMenu
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
        var previewSize: CGFloat = 40
        var onLocationChange: ((CGPoint?) -> Void)?
        var itemAt: ((CGPoint) -> String?)?
        var iconCenterForItem: ((String) -> CGPoint?)?
        var iconForItem: ((String) -> NSImage?)?
        var canDragItem: ((String) -> Bool)?
        var onClick: ((String) -> Void)?
        var onContextMenu: ((String) -> [FavoriteShelfMenuAction])?
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
        private var captureHeartbeat: Timer?
        private var preview: NSPanel?
        private var escapeMonitor: Any?
        private var pendingLocation: CGPoint?
        private var updateScheduled = false
        private var pendingDrag: (id: String, translation: CGSize, outside: Bool, x: CGFloat)?
        private var dragUpdateScheduled = false
        private var dragUpdateGeneration = 0
        private var contextMenuActions: [() -> Void] = []

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            registerForDraggedTypes([.fileURL])
        }

        required init?(coder: NSCoder) { nil }

        private var shelfRect: NSRect {
            NSRect(x: shelfInset, y: 0, width: min(shelfWidth, max(0, bounds.width - 2 * shelfInset)), height: bounds.height)
        }

        private var dragRect: NSRect {
            NSRect(x: shelfInset, y: 0, width: max(0, bounds.width - 2 * shelfInset), height: bounds.height)
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
            startPoint = convert(event.locationInWindow, from: nil)
            pressedID = itemAt?(startPoint)
            if let pressedID, let iconCenter = iconCenterForItem?(pressedID) {
                grabOffset = CGPoint(x: startPoint.x - iconCenter.x,
                                     y: startPoint.y - iconCenter.y)
            } else {
                grabOffset = .zero
            }
        }

        override func mouseDragged(with event: NSEvent) {
            guard let id = pressedID, canDragItem?(id) == true,
                  !event.modifierFlags.contains(.option) else { return }
            let location = convert(event.locationInWindow, from: nil)
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
            } else if let id, itemAt?(location) == id {
                onClick?(id)
            }
        }

        override func rightMouseDown(with event: NSEvent) {
            guard !dragging, let id = itemAt?(convert(event.locationInWindow, from: nil)),
                  let actions = onContextMenu?(id), !actions.isEmpty else { return }
            let menu = NSMenu()
            menu.autoenablesItems = false
            contextMenuActions = []
            for action in actions {
                guard let title = action.title, let perform = action.perform else {
                    if !menu.items.isEmpty { menu.addItem(.separator()) }
                    continue
                }
                let item = NSMenuItem(title: title,
                    action: #selector(performContextMenuAction(_:)), keyEquivalent: "")
                item.target = self
                item.isEnabled = action.isEnabled
                item.tag = contextMenuActions.count
                contextMenuActions.append(perform)
                menu.addItem(item)
            }
            NSMenu.popUpContextMenu(menu, with: event, for: self)
            contextMenuActions = []
        }

        @objc private func performContextMenuAction(_ sender: NSMenuItem) {
            guard contextMenuActions.indices.contains(sender.tag) else { return }
            contextMenuActions[sender.tag]()
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
            pendingLocation = nil
            onLocationChange?(nil)
        }

        private func updateLocation(_ event: NSEvent) {
            guard !dragging else { return }
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
                if !self.dragging { self.onLocationChange?(self.pendingLocation) }
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
            removalTimer?.invalidate()
            captureHeartbeat?.invalidate()
            if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        }
    }
}
