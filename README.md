# TaskDock

macOS 原生窗口级任务栏：把每一个应用窗口显示为独立任务项，直接切换到准确窗口。

[下载最新版本](https://github.com/evay-spece/TaskDock/releases/latest)

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

- accessory activation policy 和底部 `NSPanel`
- 辅助功能权限检查与系统设置请求入口
- `NSWorkspace` + Accessibility API 枚举普通 GUI 应用的独立窗口
- 标题、应用名、应用图标、最小化和焦点状态
- 点击任务项时激活应用、取消最小化并尝试 raise 精确窗口
- 2 秒轮询，以及应用启动/退出通知触发刷新
- 排除 TaskDock 自身窗口和隐藏/后台应用
- 任务项鼠标悬停放大、高亮和阴影反馈
- 没有可访问窗口的应用不会产生任务项
- 任务栏固定为桌面可用宽度的 80%，窗口较多时自动压缩任务项
- 任务项右键支持显示同一 App 的所有窗口，以及关闭当前窗口
- 任务项长按弹出同一组操作菜单
- 设置中支持 App 黑名单、显示隐藏 App 窗口、浅色/深色主题
- 设置使用独立窗口打开；当前焦点窗口使用系统强调色背景和底部高亮条标识
- 任务栏固定为桌面可用宽度的 80% 并居中；任务项按 App 启动顺序稳定排列，窗口多时自动等比压缩宽度
- 设置窗口支持从 GitHub Release 检查更新

## 当前限制

- 当前仅定位主屏幕，不处理多显示器独立任务栏。
- AX 窗口顺序和稳定身份由应用提供能力决定；刷新期间关闭的窗口会被安全忽略。
- 某些应用不实现 `kAXFocusedAttribute`、`kAXMainAttribute` 或 raise action，焦点高亮/精确激活可能退化为应用级激活。
- 尚未加入窗口缩略图、标签页枚举、拖拽排序、自动隐藏或 Dock 替换。

## 下一步最高价值修复

1. 在 Finder、Chrome/Chromium、Xcode 或 VS Code 的多窗口和最小化场景做实机验收，并记录应用差异。
2. 以 AX 窗口位置/引用变化完善稳定身份，减少刷新导致的任务项跳动。
3. 增加窗口关闭/焦点变化的 AX observer，降低轮询延迟和 CPU 使用。
