import AppKit

enum TaskbarItemWidthMode: String, CaseIterable, Identifiable {
    case fixed, adaptive
    var id: String { rawValue }
    var label: String { self == .fixed ? "固定长度" : "自适应长度" }
}

enum TaskbarItemSizing {
    static let defaultFixedWidth: CGFloat = 148
    static let minimumAdaptiveWidth: CGFloat = 80

    static func displayTitle(_ title: String, bundleIdentifier: String?) -> String {
        guard bundleIdentifier == "com.microsoft.edgemac" else { return title }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let appName = "Microsoft Edge"
        if title.compare(appName, options: .caseInsensitive) == .orderedSame { return "浏览器窗口" }
        guard let range = title.range(of: " - \(appName)", options: [.backwards, .caseInsensitive]) else { return title }
        let page = String(title[..<range.lowerBound])
        let suffix = String(title[range.upperBound...])
        guard !page.isEmpty, suffix.isEmpty || suffix.hasPrefix(" - ") else { return title }
        return page + suffix
    }

    static func adaptiveWidth(title: String, fontSize: CGFloat, scale: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize * scale, weight: .medium)
        let textWidth = (title as NSString).size(withAttributes: [.font: font]).width
        // Icon, text gap, horizontal padding, and a little rounding clearance.
        return min(defaultFixedWidth * scale, max(minimumAdaptiveWidth * scale, ceil(textWidth + 45 * scale)))
    }

    static func groupFrames(widths: [[CGFloat]], spacing: CGFloat) -> [(minX: CGFloat, maxX: CGFloat)] {
        var x: CGFloat = 0
        return widths.map { items in
            let start = x
            let width = items.reduce(0, +) + CGFloat(max(0, items.count - 1)) * spacing
            x += width + spacing
            return (start, start + width)
        }
    }
}
