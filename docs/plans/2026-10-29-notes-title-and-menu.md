# 备忘录修改：标题与 Finder 菜单

来源：直接读取 macOS 备忘录《taskdock修改》及内嵌三张配图。

- 备忘录任务项显示对应窗口编辑区所选备忘录的首行标题；不能读取时去掉集合标题末尾的备忘录数量。
- Edge 只清理标题末尾内存占用提示，保留页面正文标题；原始 AX 标题继续用于窗口匹配。
- Finder 扩展中“剪切、粘贴并移动”相邻排列，再显示“新建文件”。Finder Sync 返回的是自定义菜单项，不能控制整个 Finder 菜单中相对于原生“拷贝”的插入位置。这部分只能改善扩展内部顺序，无法完整达到截图要求。
- 不发布新版本；完成针对性自测及编译，生成本地测试构建。

## 验证结果

- 标题自测覆盖中文/英文内存后缀、普通网页标题不误删、备忘录数量后缀及首行标题提取。
- Notes 读取器与 Finder 扩展独立 typecheck 通过。
- Release 使用 macOS 26 SDK 编译成功；默认 macOS 27 SDK 缺少 SwiftUI 宏插件，未修改产品代码来绕过。
- Build 162 本地应用签名、ZIP 完整性检查通过，安装于主力机 /Applications/TaskDock.app。
- CUA 实际读取 TaskDock 按钮，备忘录任务项显示“taskdock修改”，旧版显示“iCloud全部 – 23个备忘录”。
- 当前 Edge 窗口无内存后缀，真实内存提示出现时的显示仍待观察。
- Finder 扩展内部菜单顺序已修改并编译；整个 Finder 原生菜单的最终位置仍由系统控制。
- GitHub 未发布。旧 Build 161 保留于 dist/retired/TaskDock-1.10.1-build161-before-notes-fix.app。
