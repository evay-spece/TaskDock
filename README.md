# TaskDock

macOS 原生窗口切换工具：可在任务栏与 Dock 融合栏之间切换，直接定位到准确窗口。

[下载最新版本](https://github.com/evay-spece/TaskDock/releases/latest)

## 最新版本 1.5.2（Build 48）

- 离线授权：7 天完整试用、¥59 一次购买授权；人工核款、人工邮件发码。
- “打开申请邮件”只打开草稿，需要买家补充付款信息后主动发送；也可复制申请信息到网页邮箱发送。
- 到期时恢复原系统 Dock 偏好并隐藏 TaskDock 操作面板；状态栏仍可打开设置、购买与激活及退出。
- 使用 Apple Development 签名，未办理 Developer ID 与 Apple 公证，安装可能被 macOS 拦截。
- 任务项提供固定长度与按标题自适应长度，优化收藏重排、悬停与拖动反馈。
- 最大化及左右半屏默认动画收起窗口底边；普通窗口仅处理小幅重叠，明显出屏时跳过。
- 补强最小化窗口保留、单窗口原生最小化及右下角屏幕边缘点击热区。
- 本地收费流程回归：`zsh scripts/sale-readiness-selftest.sh`。测试使用临时钥匙串、临时时钟及内存临时密钥，不修改生产公钥。
- 发布前在主力机调整好外观参数，更新版本号后运行 `python3 scripts/capture-release-appearance.py --write`，检查生成的 `Sources/TaskDock/ReleaseAppearanceSnapshot.swift`，将它随源码提交。新版本首次启动时覆盖外观参数，保留收藏、文件夹、历史记录、授权和功能开关；同版本后续启动保留用户再次调整的数值。
- 发布打包：`zsh scripts/preflight_release.sh`。预检会确认外观快照与主力机当前设置、版本号一致；可用 `TASKDOCK_OUTPUT_DIRECTORY` 指定输出位置；解包后自动核验授权资源与签名。

## 安装

1. 从 Releases 下载并解压 `TaskDock`。
2. 打开 TaskDock。
3. 在“系统设置 → 隐私与安全性 → 辅助功能”中允许 TaskDock。

TaskDock 不需要屏幕录制权限。

## 构建与运行

需要 macOS 12+、Swift 5.9+ 和 AppKit。

```bash
swift build
swift run
```

推荐以后统一使用固定启动脚本：

```bash
./scripts/build-and-run.sh
```

应用始终位于项目内的 `AppBundle/TaskDock.app`。脚本会优先使用本机 Apple Development 签名；没有开发签名时使用临时签名。

首次启动时点击“打开设置”，在“系统设置 → 隐私与安全性 → 辅助功能”中允许 TaskDock。程序不请求屏幕录制权限。

## 已实现

- accessory activation policy 和自适应 `NSPanel`
- 辅助功能权限检查与系统设置请求入口
- `NSWorkspace` + Accessibility API 枚举普通 GUI 应用的独立窗口
- 标题、应用名、应用图标、最小化和焦点状态
- 设置中可随时切换“任务栏”与“Dock 融合”，无需重启
- 任务栏模式左右铺满屏幕，内容两侧留白可调；空间不足时自动压缩窗口卡片
- 点击窗口卡片时激活应用、取消最小化并尝试 raise 精确窗口
- 窗口卡片支持悬停、焦点高亮、最小化标记、右键和长按菜单
- 没有可访问窗口的应用不会产生任务项
- 设置中支持 App 黑名单；非选中项透明度与窗口显示可按模式分别设置，外观固定为深色
- 当前焦点窗口仅增加透明白底提亮，不使用强调色背景或描边；底部强调色指示条保留
- 设置窗口支持从 GitHub Release 检查更新、下载安装包并自动重启，无需手动下载
- 支持拖动窗口卡片，以 App 为整体调整任务项顺序
- 自动过滤 ChatGPT/Codex 的 Computer Use 内部窗口
- 点击非焦点窗口卡片会显示并置顶；点击当前焦点窗口卡片会最小化
- 可从设置或菜单切换任务栏与 Dock 融合模式；点击系统 Dock 中的 TaskDock 图标可恢复隐藏状态
- 使用独立 TaskDock macOS 图标，并由构建脚本自动生成完整 `.icns`
- App 分组拖动采用跟手预览，松手后一次性落位
- 默认双击 `Option` 键隐藏或显示 TaskDock，可在设置中改为双击 `Command` 或 `Control`
- 监听 App 主窗口、焦点窗口和最小化状态变化，并以 0.7 秒轮询作为后备刷新
- 任务栏提供收藏 App、最近打开的非收藏 App（最多 10 个）、收藏文件夹和运行指示灯；默认收藏“下载”文件夹
- 收藏图标悬停时平滑放大，可调整为 1.2–2.4 倍并保留两端安全区域；任务项文字支持 8、9、10、11、12 五档
- 临时隐藏任务栏时恢复用户原有的系统 Dock 偏好，任务栏重新显示时再次隐藏系统 Dock
- Dock 融合模式将 Finder 窗口置于系统 Dock 左侧，其他多窗口 App 置于右侧；单窗口 App 默认不占用右侧空间
- Dock 融合模式中同一 App 达到 3 个窗口时默认折叠为一个入口，点击可选择具体窗口；门槛可在设置中调整
- Dock 融合模式可临时显示 5 分钟内使用过、尚未达到显示门槛的最多 2 个窗口；遵守手动隐藏的 App 设置，可关闭
- 仅调整外观时直接重绘；拖动任务栏高度时先更新布局，停手后再同步窗口占用区域

偏好迁移自测可运行：

```bash
swiftc Sources/TaskDockPreferences/ModePreferenceStorage.swift scripts/mode-preference-selftest.swift -o /tmp/taskdock-mode-preference-selftest
/tmp/taskdock-mode-preference-selftest
```

## Finder 右键功能

右键功能及其设置入口默认关闭、隐藏。获得设置入口后，可在“右键功能”页开启功能、勾选和排序新建类型，并添加自定义扩展名。隐藏设置入口不会关闭已经启用的功能。Finder 右键的“新建文件”子菜单支持 Excel、Word、TXT、CSV、Markdown 和 RTF；Excel、Word 使用空白文档模板，自定义类型创建空白文件。

选中文件后右键“剪切”或按 ⌘X，在目标文件夹按 ⌘V 或右键“粘贴并移动”。移动成功后源文件消失，同名冲突不会覆盖。快捷键仅在 Finder 文件浏览区域生效，重命名和搜索输入框保留文字编辑快捷键。首次使用可在设置中点“授权并测试 ⌘X”。

应用内嵌 `com.taskdock.app.finder` 扩展，开发构建和打包脚本会编译、签名并复制模板。原独立版的文件类型设置会在首次启动时迁移到 TaskDock。

文件操作自测：

```bash
swiftc Sources/TaskDock/FileTypeSettings.swift Sources/TaskDock/FileCreator.swift Sources/TaskDock/ClipboardCutter.swift scripts/finder-file-actions-selftest.swift -o /tmp/taskdock-finder-file-actions-selftest
/tmp/taskdock-finder-file-actions-selftest
```

## 当前限制

- 当前仅定位主屏幕。
- AX 窗口顺序和稳定身份由应用提供能力决定；刷新期间关闭的窗口会被安全忽略。
- 某些应用不实现 `kAXFocusedAttribute`、`kAXMainAttribute` 或 raise action，焦点高亮/精确激活可能退化为应用级激活。
- macOS 公共接口不允许把系统最小化动画改到 TaskDock；当前快速同步最小化状态。
- 尚未加入窗口缩略图或系统 Dock 完整替换。

## 下一步最高价值修复

1. 在 Finder、Chrome/Chromium、Xcode 或 VS Code 的多窗口和最小化场景做实机验收，并记录应用差异。
2. 以 AX 窗口位置/引用变化完善稳定身份，减少刷新导致的窗口卡片跳动。
3. 根据实机能耗数据继续降低后备轮询频率。
