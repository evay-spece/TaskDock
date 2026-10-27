import AppKit

@MainActor
final class TaskbarCollapseAnimator {
    private var overlays: [NSPanel] = []

    func collapse(window: WindowModel, from accessibilityFrame: CGRect?, toward target: CGPoint) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(target) }),
              let primaryScreen = NSScreen.screens.first else { return }

        let windowCenter = accessibilityFrame.map {
            CGPoint(x: $0.midX, y: primaryScreen.frame.maxY - $0.midY)
        }
        let sourceCenter = windowCenter.flatMap { screen.frame.contains($0) ? $0 : nil }
            ?? CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY)

        let start = CGRect(x: sourceCenter.x - 130, y: sourceCenter.y - 42, width: 260, height: 84)
        let end = CGRect(x: target.x - 22, y: target.y - 16, width: 44, height: 32)
        let overlay = NSPanel(
            contentRect: start,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        overlay.level = .screenSaver
        overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        overlay.ignoresMouseEvents = true
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.appearance = TaskDockAppearance.fixed
        overlay.hasShadow = true

        let background = NSVisualEffectView(frame: CGRect(origin: .zero, size: start.size))
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 16
        background.layer?.masksToBounds = true
        overlay.contentView = background

        let icon = NSImageView(frame: CGRect(x: 18, y: 18, width: 48, height: 48))
        icon.image = window.applicationIcon
        icon.imageScaling = .scaleProportionallyUpOrDown
        background.addSubview(icon)

        let title = NSTextField(labelWithString: window.title)
        title.frame = CGRect(x: 78, y: 22, width: 164, height: 40)
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        title.textColor = .labelColor
        title.lineBreakMode = .byTruncatingTail
        background.addSubview(title)

        overlays.append(overlay)
        overlay.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.32
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            overlay.animator().setFrame(end, display: true)
            overlay.animator().alphaValue = 0
        } completionHandler: { [weak self, weak overlay] in
            Task { @MainActor in
                overlay?.orderOut(nil)
                if let overlay { self?.overlays.removeAll { $0 === overlay } }
            }
        }
    }
}
