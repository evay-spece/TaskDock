import Foundation
@main struct WindowDisplayTitleSelfTest {
    static func main() {
        func title(_ raw: String, _ app: String = "com.microsoft.edgemac", note: String? = nil) -> String {
            WindowDisplayTitle.resolve(rawTitle: raw, applicationName: "备忘录", bundleIdentifier: app, selectedNoteTitle: note)
        }
        precondition(title("iCloud全部 – 23个备忘录", "com.apple.Notes", note: "项目安排") == "项目安排")
        precondition(title("iCloud全部 – 23个备忘录", "com.apple.Notes") == "iCloud全部")
        precondition(title("All iCloud – 23 notes", "com.apple.Notes") == "All iCloud")
        precondition(title("独立备忘录", "com.apple.Notes") == "独立备忘录")
        precondition(WindowDisplayTitle.noteTitle(from: "标题\n正文保留在备忘录中") == "标题")
        precondition(WindowDisplayTitle.noteTitle(from: "\n正文不能代替标题") == nil)
        for raw in ["店铺运营详情页 - 内存使用量高 - 1.0 GB", "店铺运营详情页 — 内存使用量高 — 1.0 GB…"] {
            precondition(title(raw) == "店铺运营详情页", raw)
        }
        precondition(title("店铺运营详情页 - High memory usage: 1.0 GB - Microsoft Edge") == "店铺运营详情页 - Microsoft Edge")
        precondition(title("商品列表 - 内存使用量高 - 835 MB - evay") == "商品列表 - evay")
        precondition(title("内存使用量高的原因 - Microsoft Edge") == "内存使用量高的原因 - Microsoft Edge")
        precondition(title("教程 - Memory usage in Swift") == "教程 - Memory usage in Swift")
        precondition(title("教程 - 内存使用量高 - 1.0 GB", "com.apple.Safari") == "教程 - 内存使用量高 - 1.0 GB")
        print("WINDOW_DISPLAY_TITLE_OK")
    }
}
