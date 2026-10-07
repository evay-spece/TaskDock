import AppKit

/// Matches the shelf's native hover-name bubble, with a downward tail above the icon.
final class FavoriteDragPreviewView: NSView {
    private let imageView = NSImageView()
    private let bubble = CAShapeLayer()
    private let textLayer = CATextLayer()
    private let iconSize: CGFloat

    init(icon: NSImage?, iconSize: CGFloat) {
        self.iconSize = iconSize
        super.init(frame: NSRect(x: 0, y: 0, width: 140, height: iconSize + 70))
        wantsLayer = true
        layer?.masksToBounds = false
        imageView.image = icon
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.alphaValue = 0.8
        addSubview(imageView)
        bubble.fillColor = NSColor(calibratedWhite: 0.96, alpha: 0.97).cgColor
        bubble.strokeColor = NSColor(calibratedWhite: 0.55, alpha: 0.50).cgColor
        bubble.lineWidth = 0.75
        bubble.shadowColor = NSColor.black.cgColor
        bubble.shadowOpacity = 0.20
        bubble.shadowRadius = 7
        bubble.shadowOffset = CGSize(width: 0, height: -2)
        textLayer.string = "移除收藏"
        textLayer.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        textLayer.fontSize = 14
        textLayer.alignmentMode = .center
        textLayer.foregroundColor = NSColor(calibratedWhite: 0.08, alpha: 1).cgColor
        bubble.addSublayer(textLayer)
        layer?.addSublayer(bubble)
        setReady(false)
    }

    required init?(coder: NSCoder) { nil }

    func setReady(_ ready: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bubble.opacity = ready ? 1 : 0
        imageView.alphaValue = ready ? 0.65 : 0.8
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        imageView.frame = NSRect(x: (bounds.width - iconSize) / 2, y: 8, width: iconSize, height: iconSize)
        let width: CGFloat = 88
        let height: CGFloat = 38
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
        bubble.frame = NSRect(x: (bounds.width - width) / 2, y: iconSize + 16, width: width, height: height)
        bubble.path = path
        bubble.shadowPath = path
        textLayer.frame = NSRect(x: 6, y: tail + 6, width: width - 12, height: 20)
        textLayer.contentsScale = window?.backingScaleFactor ?? 2
        CATransaction.commit()
    }
}
