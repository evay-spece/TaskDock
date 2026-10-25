import AppKit

/// Matches the shelf's native hover-name bubble, with a downward tail above the icon.
final class FavoriteDragPreviewView: NSView {
    private let imageView = NSImageView()
    private let bubble = FloatingBubbleHintView(title: "移除收藏", width: 80, fontSize: SmallBubbleMetrics.fontSize, arrowX: 40)
    private let iconSize: CGFloat
    private var settingsObserver: NSObjectProtocol?

    init(icon: NSImage?, iconSize: CGFloat) {
        self.iconSize = iconSize
        super.init(frame: NSRect(origin: .zero, size: Self.requiredSize(iconSize: iconSize)))
        wantsLayer = true
        layer?.masksToBounds = false
        imageView.image = icon
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.alphaValue = 0.8
        addSubview(imageView)
        addSubview(bubble)
        setReady(false)
        settingsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: UserDefaults.standard, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let size = Self.requiredSize(iconSize: self.iconSize)
            self.window?.setContentSize(size)
            self.setFrameSize(size)
            self.needsLayout = true
        }
    }

    static func requiredSize(iconSize: CGFloat) -> NSSize {
        let font = NSFont.systemFont(ofSize: SmallBubbleMetrics.fontSize, weight: .regular)
        let textWidth = ceil(("移除收藏" as NSString).size(withAttributes: [.font: font]).width) + 28
        return NSSize(width: max(140, iconSize + 16, textWidth + 16),
                      height: iconSize + 16 + SmallBubbleMetrics.iconGap + SmallBubbleMetrics.height)
    }

    deinit {
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
    }

    required init?(coder: NSCoder) { nil }

    func setReady(_ ready: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bubble.isHidden = !ready
        imageView.alphaValue = ready ? 0.65 : 0.8
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        imageView.frame = NSRect(x: (bounds.width - iconSize) / 2, y: 8, width: iconSize, height: iconSize)
        let font = NSFont.systemFont(ofSize: SmallBubbleMetrics.fontSize, weight: .regular)
        let width = max(80, ceil(("移除收藏" as NSString).size(withAttributes: [.font: font]).width) + 28)
        bubble.update(title: "移除收藏", width: width, fontSize: SmallBubbleMetrics.fontSize, arrowX: width / 2)
        let height = SmallBubbleMetrics.height
        let tail: CGFloat = 7
        let radius: CGFloat = 14
        let center = width / 2
        let path = CGMutablePath()
        path.move(to: CGPoint(x: radius, y: tail))
        path.addLine(to: CGPoint(x: center - tail, y: tail))
        path.addLine(to: CGPoint(x: center, y: 0))
        path.addLine(to: CGPoint(x: center + tail, y: tail))
        path.addLine(to: CGPoint(x: width - radius, y: tail))
        path.addQuadCurve(to: CGPoint(x: width, y: tail + radius), control: CGPoint(x: width, y: tail))
        path.addLine(to: CGPoint(x: width, y: height - radius))
        path.addQuadCurve(to: CGPoint(x: width - radius, y: height), control: CGPoint(x: width, y: height))
        path.addLine(to: CGPoint(x: radius, y: height))
        path.addQuadCurve(to: CGPoint(x: 0, y: height - radius), control: CGPoint(x: 0, y: height))
        path.addLine(to: CGPoint(x: 0, y: tail + radius))
        path.addQuadCurve(to: CGPoint(x: radius, y: tail), control: CGPoint(x: 0, y: tail))
        path.closeSubpath()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bubble.frame = NSRect(x: (bounds.width - width) / 2, y: imageView.frame.maxY + SmallBubbleMetrics.iconGap, width: width, height: height)
        CATransaction.commit()
    }
}
