# 设置滑杆统一为 macOS 27 系统样式

- 任务栏和开发者页共用 ReleaseTunedSlider，统一从 NSSlider 封装改为 SwiftUI 原生 Slider；不添加自绘玻璃覆盖层。
- 保留连续值绑定、实时预览/保存、默认标记、1.2% 范围内默认值吸附和对齐触觉反馈。默认标记不拦截输入。
- 使用完整 Xcode 的 macOS 27 SDK 构建。此前仅指定 --sdk 时，SwiftPM 产物 LC_BUILD_VERSION 的 sdk 为 12.0；显式传递 linker platform_version 后记录 sdk 27.0、最低系统 12.0。
- scripts/preflight_release.sh 和 scripts/build-and-run.sh 自动优先使用完整 Xcode，并将实际 SDK 版本传给链接器，避免后续打包退回旧设计。环境指定的 DEVELOPER_DIR / TASKDOCK_BUILD_SDK 仍优先。
- 构建验证：Release 编译、脚本语法检查、签名、ZIP 完整性检查；vtool 确认 minos 12.0 / sdk 27.0。
- 实机验证：设置任务栏页滑杆显示原生新样式，两个并排滑杆及默认标记排版正常；透明度设为 0.25 后即刻显示 25%，已恢复原值 0.05717522504091654；高度设为 54.2 后吸附到默认 54。
- Build 168 已安装主力机，Build 167 保留备份。GitHub 未发布。

本地构建配置：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build -c release \
  --sdk /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.sdk \
  -Xlinker -platform_version -Xlinker macos -Xlinker 12.0 -Xlinker 27.0
```
