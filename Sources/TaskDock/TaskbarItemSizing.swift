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

struct TaskbarOverflowGroup {
    let id: String
    let expandedWidth: CGFloat
    let collapsedWidth: CGFloat
    let isAlreadyCollapsed: Bool
    let containsFocusedWindow: Bool
}

enum TaskbarOverflowLayout {
    static func additionalCollapsedIDs(
        groups: [TaskbarOverflowGroup], precedingItemWidths: [CGFloat],
        availableWidth: CGFloat, spacing: CGFloat, leadingPadding: CGFloat = 0
    ) -> Set<String> {
        guard availableWidth.isFinite, availableWidth > 0 else { return [] }
        let itemCount = groups.count + precedingItemWidths.count
        var requiredWidth = leadingPadding + precedingItemWidths.reduce(0, +)
            + groups.reduce(0) { $0 + ($1.isAlreadyCollapsed ? $1.collapsedWidth : $1.expandedWidth) }
            + CGFloat(max(itemCount - 1, 0)) * spacing
        guard requiredWidth > availableWidth else { return [] }

        let candidates = groups.enumerated().filter {
            !$0.element.isAlreadyCollapsed && $0.element.collapsedWidth < $0.element.expandedWidth
        }.sorted { lhs, rhs in
            if lhs.element.containsFocusedWindow != rhs.element.containsFocusedWindow {
                return !lhs.element.containsFocusedWindow
            }
            let lhsSaving = lhs.element.expandedWidth - lhs.element.collapsedWidth
            let rhsSaving = rhs.element.expandedWidth - rhs.element.collapsedWidth
            return lhsSaving == rhsSaving ? lhs.offset < rhs.offset : lhsSaving > rhsSaving
        }
        var collapsed = Set<String>()
        for candidate in candidates {
            collapsed.insert(candidate.element.id)
            requiredWidth -= candidate.element.expandedWidth - candidate.element.collapsedWidth
            if requiredWidth <= availableWidth { break }
        }
        return collapsed
    }
}
