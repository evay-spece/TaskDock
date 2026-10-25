import AppKit
import SwiftUI

extension View {
    func floatingBubbleWindow<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: () -> Content) -> some View {
        background(LeadingArrowPopoverAnchor(isPresented: isPresented, content: AnyView(content())))
    }
    func floatingBubbleContextMenu(actions: [FavoriteShelfMenuAction], iconCenterX: CGFloat? = nil, onVisibilityChange: @escaping (Bool) -> Void) -> some View {
        overlay(FloatingBubbleContextAnchor(actions: actions, iconCenterX: iconCenterX, onVisibilityChange: onVisibilityChange))
    }
}

private struct FloatingBubbleContextAnchor: NSViewRepresentable {
    let actions: [FavoriteShelfMenuAction]
    let iconCenterX: CGFloat?
    let onVisibilityChange: (Bool) -> Void
    func makeNSView(context: Context) -> ContextView { ContextView() }
    func updateNSView(_ view: ContextView, context: Context) {
        view.actions = actions
        view.iconCenterX = iconCenterX
        view.onVisibilityChange = onVisibilityChange
    }
    static func dismantleNSView(_ view: ContextView, coordinator: ()) { view.presenter.close() }

    final class ContextView: NSView {
        let presenter = LeadingArrowPopoverAnchor.Coordinator()
        var actions: [FavoriteShelfMenuAction] = []
        var iconCenterX: CGFloat?
        var onVisibilityChange: ((Bool) -> Void)?
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent,
                  event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control)) else { return nil }
            return super.hitTest(point)
        }
        override func mouseDown(with event: NSEvent) { rightMouseDown(with: event) }
        override func rightMouseDown(with event: NSEvent) {
            guard !actions.isEmpty else { return }
            presenter.close()
            presenter.dismiss = { [weak self] in self?.presenter.close() }
            presenter.didClose = { [weak self] in self?.onVisibilityChange?(false) }
            presenter.shouldShow = true
            presenter.show(AnyView(FloatingBubbleActionList(actions: actions) { [weak self] action in
                self?.presenter.close()
                action()
            }), relativeTo: self, iconCenterX: iconCenterX)
            onVisibilityChange?(true)
        }
    }
}

private struct FloatingBubbleActionList: View {
    let actions: [FavoriteShelfMenuAction]
    let onSelect: (() -> Void) -> Void
    @State private var hovered: Int?
    var body: some View {
        VStack(spacing: 0) {
            ForEach(actions.indices, id: \.self) { index in
                let action = actions[index]
                if let title = action.title, let perform = action.perform {
                    Button { onSelect(perform) } label: {
                        HStack(spacing: 8) {
                            if let symbol = action.symbol { Image(systemName: symbol).frame(width: 16) }
                            Text(title)
                            Spacer(minLength: 0)
                        }.font(.system(size: 13)).padding(.horizontal, 9).frame(height: 29)
                            .foregroundStyle(hovered == index ? Color.white : Color.primary)
                            .background(RoundedRectangle(cornerRadius: 6).fill(hovered == index ? Color.accentColor : .clear))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).dockMenuFocusAppearance().disabled(!action.isEnabled)
                        .onHover { hovered = $0 ? index : nil }
                } else { Divider().padding(.horizontal, 9).padding(.vertical, 5) }
            }
        }.padding(5).frame(width: 240)
    }
}

private struct LeadingArrowPopoverAnchor: NSViewRepresentable {
    @Binding var isPresented: Bool
    let content: AnyView

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { AnchorView(frame: .zero) }
    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        coordinator.dismiss = { isPresented = false }
        coordinator.shouldShow = isPresented
        if isPresented {
            DispatchQueue.main.async { [weak view, weak coordinator] in
                guard let view, let coordinator, coordinator.shouldShow, view.window != nil else { return }
                coordinator.show(content, relativeTo: view)
            }
        } else { coordinator.close() }
    }
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.close() }

    final class AnchorView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    final class Coordinator {
        var dismiss: (() -> Void)?
        var shouldShow = false
        var didClose: (() -> Void)?
        private var panel: ArrowPanel?
        private var localMonitor: Any?
        private var globalMonitor: Any?

        func show(_ content: AnyView, relativeTo anchor: NSView, iconCenterX: CGFloat? = nil) {
            guard let parent = anchor.window, parent.isVisible, !parent.isMiniaturized,
                  !anchor.isHiddenOrHasHiddenAncestor else { close(); return }
            let rect = parent.convertToScreen(anchor.convert(anchor.bounds, to: nil))
            let targetX = iconCenterX.map { offset in
                parent.convertPoint(toScreen: anchor.convert(NSPoint(
                    x: anchor.bounds.minX + min(max(offset, 0), anchor.bounds.width),
                    y: anchor.bounds.midY), to: nil)).x
            } ?? rect.midX
            let visible = (parent.screen ?? NSScreen.main)?.visibleFrame ?? rect.insetBy(dx: -500, dy: -500)
            let host = NSHostingView(rootView: content)
            let size = host.fittingSize
            let width = max(260, min(size.width, visible.width - 16))
            let height = size.height + 10
            let x = min(max(targetX - 30, visible.minX + 8), visible.maxX - width - 8)
            let arrowX = min(max(targetX - x, 18), width - 18)
            let y = min(rect.maxY + 14, visible.maxY - height - 8)
            let root = AnyView(FloatingBubbleSurface(arrowX: arrowX) { content })
            if let existing = panel, let hosting = existing.contentView as? NSHostingView<AnyView> {
                hosting.rootView = root
                existing.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
                return
            }
            let window = ArrowPanel(contentRect: NSRect(x: x, y: y, width: width, height: height),
                                    styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.level = .popUpMenu
            window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = false
            window.dismiss = { [weak self] in self?.dismiss?() }
            window.contentView = NSHostingView(rootView: root)
            panel = window
            parent.addChildWindow(window, ordered: .above)
            window.makeKeyAndOrderFront(nil)
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
                guard let self else { return event }
                if event.type == .keyDown, event.keyCode == 53 { self.dismiss?(); return nil }
                if event.type != .keyDown, event.window !== self.panel,
                   !rect.contains(NSEvent.mouseLocation) { self.dismiss?() }
                return event
            }
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.dismiss?()
            }
        }
        func close() {
            let wasOpen = panel != nil
            shouldShow = false
            if let localMonitor { NSEvent.removeMonitor(localMonitor) }
            if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
            localMonitor = nil; globalMonitor = nil
            if let panel { panel.parent?.removeChildWindow(panel); panel.orderOut(nil); panel.close() }
            panel = nil
            if wasOpen { didClose?() }
        }
        deinit { close() }
    }
}

private final class ArrowPanel: NSPanel {
    var dismiss: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { dismiss?() }
}

struct FloatingBubbleSurface<Content: View>: View {
    let arrowX: CGFloat
    var isSmall = false
    @ViewBuilder let content: () -> Content
    @AppStorage(DeveloperDebugSettings.bubbleTransparencyKey) private var transparency = 0.0
    private var backgroundOpacity: Double {
        transparency.isFinite ? 1 - min(0.9, max(0, transparency)) : 1
    }
    var body: some View {
        content().padding(.bottom, isSmall ? SmallBubbleMetrics.tailHeight : 10)
            .background(FrostedBubbleBackground(arrowX: arrowX, isSmall: isSmall).opacity(backgroundOpacity))
            .overlay(FloatingBubbleShape(arrowX: arrowX, isSmall: isSmall).stroke(Color.primary.opacity(0.26), lineWidth: 0.5))
    }
}

/// Compact capsule hints share the glass material while keeping their own outline.
enum SmallBubbleMetrics {
    static var fontSize: CGFloat { value(DeveloperDebugSettings.smallBubbleFontSizeKey, fallback: 12, range: 9...20) }
    static var iconGap: CGFloat { value(DeveloperDebugSettings.smallBubbleIconGapKey, fallback: 3, range: 0...30) }
    static let textVerticalPadding: CGFloat = 12
    static let tailHeight: CGFloat = 6
    static var height: CGFloat { fontSize + textVerticalPadding + tailHeight }
    private static func value(_ key: String, fallback: Double, range: ClosedRange<Double>) -> CGFloat {
        let number = (UserDefaults.standard.object(forKey: key) as? NSNumber)?.doubleValue ?? fallback
        return CGFloat(number.isFinite ? min(range.upperBound, max(range.lowerBound, number)) : fallback)
    }
}

final class FloatingBubbleHintView: NSHostingView<AnyView> {
    private var previous: (String, CGFloat, CGFloat, CGFloat)?
    required init(rootView: AnyView) { super.init(rootView: rootView) }
    convenience init(title: String, width: CGFloat, fontSize: CGFloat, arrowX: CGFloat) {
        self.init(rootView: AnyView(EmptyView()))
        update(title: title, width: width, fontSize: fontSize, arrowX: arrowX)
    }
    @MainActor required dynamic init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    func update(title: String, width: CGFloat, fontSize: CGFloat, arrowX: CGFloat) {
        if let previous, previous.0 == title, previous.1 == width,
           previous.2 == fontSize, previous.3 == arrowX { return }
        previous = (title, width, fontSize, arrowX)
        rootView = AnyView(FloatingBubbleSurface(arrowX: arrowX, isSmall: true) {
            Text(title).font(.system(size: fontSize, weight: .regular))
                .foregroundStyle(Color.primary).lineLimit(1)
                .frame(width: width, height: fontSize + SmallBubbleMetrics.textVerticalPadding)
        })
    }
}

private struct FrostedBubbleBackground: NSViewRepresentable {
    let arrowX: CGFloat
    var isSmall = false
    func makeNSView(context: Context) -> FrostedView {
        let view = FrostedView()
        view.material = isSmall ? .toolTip : .popover
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = false
        view.arrowX = arrowX
        view.isSmall = isSmall
        return view
    }
    func updateNSView(_ view: FrostedView, context: Context) {
        view.arrowX = arrowX
        view.isSmall = isSmall
        view.material = isSmall ? .toolTip : .popover
        view.needsLayout = true
    }
    final class FrostedView: NSVisualEffectView {
        var arrowX: CGFloat = 30
        var isSmall = false
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func layout() {
            super.layout()
            guard bounds.width > 0, bounds.height > 10 else { return }
            let size = bounds.size
            let path = FloatingBubbleShape(arrowX: arrowX, isSmall: isSmall).path(in: CGRect(origin: .zero, size: size)).cgPath
            maskImage = NSImage(size: size, flipped: true) { _ in
                guard let context = NSGraphicsContext.current?.cgContext else { return false }
                context.setFillColor(NSColor.black.cgColor)
                context.addPath(path)
                context.fillPath()
                return true
            }
        }
    }
}

private struct FloatingBubbleShape: Shape {
    let arrowX: CGFloat
    var isSmall = false
    func path(in rect: CGRect) -> Path {
        let tail: CGFloat = isSmall ? SmallBubbleMetrics.tailHeight : 10
        let bottom = rect.maxY - tail
        let r: CGFloat = isSmall ? min(bottom / 2, rect.width / 2) : 12
        let scale: CGFloat = isSmall ? 0.6 : 1
        let a = arrowX
        var p = Path()
        p.move(to: CGPoint(x: r, y: 0))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: 0))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: r), control: CGPoint(x: rect.maxX, y: 0))
        p.addLine(to: CGPoint(x: rect.maxX, y: bottom - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: bottom), control: CGPoint(x: rect.maxX, y: bottom))
        // Horizontal tangents at both shoulders and a rounded tip keep the
        // pointer continuous with the bottom edge instead of looking attached.
        let minimumShoulder: CGFloat = isSmall ? 6 : 12
        let shoulder = min(isSmall ? 11 : 18, max(minimumShoulder, a - r), max(minimumShoulder, rect.maxX - a - r))
        p.addLine(to: CGPoint(x: a + shoulder, y: bottom))
        p.addCurve(to: CGPoint(x: a + 7 * scale, y: bottom + 6 * scale),
                   control1: CGPoint(x: a + shoulder - 6 * scale, y: bottom),
                   control2: CGPoint(x: a + 11 * scale, y: bottom + 2 * scale))
        p.addCurve(to: CGPoint(x: a, y: rect.maxY),
                   control1: CGPoint(x: a + 3 * scale, y: rect.maxY),
                   control2: CGPoint(x: a + 2 * scale, y: rect.maxY))
        p.addCurve(to: CGPoint(x: a - 7 * scale, y: bottom + 6 * scale),
                   control1: CGPoint(x: a - 2 * scale, y: rect.maxY),
                   control2: CGPoint(x: a - 3 * scale, y: rect.maxY))
        p.addCurve(to: CGPoint(x: a - shoulder, y: bottom),
                   control1: CGPoint(x: a - 11 * scale, y: bottom + 2 * scale),
                   control2: CGPoint(x: a - shoulder + 6 * scale, y: bottom))
        p.addLine(to: CGPoint(x: r, y: bottom))
        p.addQuadCurve(to: CGPoint(x: 0, y: bottom - r), control: CGPoint(x: 0, y: bottom))
        p.addLine(to: CGPoint(x: 0, y: r))
        p.addQuadCurve(to: CGPoint(x: r, y: 0), control: .zero)
        p.closeSubpath()
        return p
    }
}
