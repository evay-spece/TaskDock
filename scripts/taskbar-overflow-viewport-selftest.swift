import AppKit
import SwiftUI

private final class Reports {
    var width: CGFloat = -1
    var collapsed: Set<String> = []
}
private struct Probe: NSViewRepresentable {
    let width: CGFloat
    let collapsed: Set<String>
    let reports: Reports
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        reports.width = width
        reports.collapsed = collapsed
    }
}
private struct Fixture: View {
    let reports: Reports
    let groups = [
        TaskbarOverflowGroup(id: "edge", windowCount: 4, expandedWidth: 600, collapsedWidth: 148,
            isAlreadyCollapsed: false, containsFocusedWindow: false),
        TaskbarOverflowGroup(id: "finder", windowCount: 2, expandedWidth: 300, collapsedWidth: 148,
            isAlreadyCollapsed: false, containsFocusedWindow: true),
        TaskbarOverflowGroup(id: "single", windowCount: 1, expandedWidth: 148, collapsedWidth: 148,
            isAlreadyCollapsed: false, containsFocusedWindow: false)
    ]
    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 350) // Favorites, folders, recent apps.
            TaskbarItemLane { width in
                let collapsed = TaskbarOverflowLayout.additionalCollapsedIDs(groups: groups,
                    precedingItemWidths: [], availableWidth: width, spacing: 4)
                HStack(spacing: 4) {
                    ForEach(groups, id: \.id) { group in
                        Text(group.id).frame(width: collapsed.contains(group.id)
                            ? group.collapsedWidth : group.expandedWidth, height: 54)
                    }
                }
                .background(Probe(width: width, collapsed: collapsed, reports: reports))
            }
            Color.clear.frame(width: 86) // Reserved trailing margin/control.
        }
    }
}
@main
struct TaskbarOverflowViewportSelfTest {
    @MainActor static func main() {
        _ = NSApplication.shared
        let reports = Reports()
        let host = NSHostingView(rootView: Fixture(reports: reports))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1600, height: 54),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        func check(_ total: CGFloat, _ expected: Set<String>) {
            window.setContentSize(NSSize(width: total, height: 54))
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            precondition(abs(reports.width - (total - 436)) < 0.5,
                "Viewport wrong: \(reports.width), total \(total)")
            precondition(reports.collapsed == expected,
                "Collapse wrong at \(total): \(reports.collapsed)")
        }
        check(1600, [])
        check(1200, ["edge"])
        check(960, ["edge", "finder"])
        check(1600, [])
        check(1200, ["edge"])
        window.orderOut(nil)
        print("TASKBAR_OVERFLOW_VIEWPORT_OK favorites right-control narrow resize expand repeat")
    }
}
