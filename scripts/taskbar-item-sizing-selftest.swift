import AppKit

@main
struct TaskbarItemSizingSelfTest {
    static func main() {
        precondition(TaskbarItemWidthMode(rawValue: "adaptive") == .adaptive)
        let short = TaskbarItemSizing.adaptiveWidth(title: "微信", fontSize: 12, scale: 1)
        let long = TaskbarItemSizing.adaptiveWidth(title: String(repeating: "长标题", count: 30), fontSize: 12, scale: 1)
        precondition(short == 80 && long == TaskbarItemSizing.defaultFixedWidth)
        precondition(TaskbarItemSizing.adaptiveWidth(title: String(repeating: "长标题", count: 30), fontSize: 12, scale: 2) == 296)
        precondition(TaskbarItemSizing.adaptiveWidth(title: "微信", fontSize: 12, scale: 2) == 2 * short)
        precondition(TaskbarItemSizing.adaptiveWidth(title: "", fontSize: 12, scale: 1) == 80)
        precondition(TaskbarItemSizing.displayTitle("页面 - Microsoft Edge - 用户", bundleIdentifier: "com.microsoft.edgemac") == "页面 - 用户")
        precondition(TaskbarItemSizing.displayTitle("Microsoft Edge", bundleIdentifier: "com.microsoft.edgemac") == "浏览器窗口")
        precondition(TaskbarItemSizing.displayTitle("文件 - Microsoft Edge", bundleIdentifier: "other") == "文件 - Microsoft Edge")
        let frames = TaskbarItemSizing.groupFrames(widths: [[72, 220], [100], [148, 88]], spacing: 4)
        precondition(frames.count == 3)
        precondition(frames[0].minX == 0 && frames[0].maxX == 296)
        precondition(frames[1].minX == 300 && frames[1].maxX == 400)
        precondition(frames[2].minX == 404 && frames[2].maxX == 644)
        precondition(TaskbarItemSizing.groupFrames(widths: [], spacing: 4).isEmpty)
        print("TASKBAR_ITEM_SIZING_OK titles scale bounds variable-width-group-geometry")
    }
}
