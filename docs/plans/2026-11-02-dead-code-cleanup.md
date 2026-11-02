# 1.12.0后第一轮代码清理

授权：用户在审查结果后要求“继续”。本轮只处理已确认停用的生产代码及说明，不迁移隐藏布局参数，不退役原生Dock实验的恢复逻辑，不改变用户参数。

移除旧指针抬脚入口、旧重试/状态/几何和旧设置UI；现行动画抽出为WindowAvoidanceAnimation并保持历史动画时长key不变。融合模式的窗口预留和动画保留。

删除未调用的旧激活弹窗壳、菜单、气泡Shape、两套停用的强制默认值迁移及对应旧测试。旧ReleaseDefaults170文件还承载实际在用的EasterEggSettingsEntryReset，独立到同名文件保留；新测试覆盖新build隐藏入口、同build不重置和个人设置保留。

简化玻璃configure，移除已经没有模式切换作用的参数和重建分支；保留进程内系统参数隔离、手动通透度调节和旧系统兼容路径。

说明修正：固定任务栏外观；胶囊强度仅调整普通状态，遮挡增强另有固定底色；出屏阈值说明补充任务项临时增强关系。

原生Dock实验仅删除未使用的设置视图，后台控制与原Dock恢复快照保留。隐藏宽度/折叠参数继续沿用用户保存值。本轮不发布。

验证完成：Release完整构建、签名、SDK27/minOS12；WINDOW_AVOIDANCE_ANIMATION_OK、STANDARD_LAYOUT_ONCE_OK、WINDOW_SPACE_RESERVATION_OK、玻璃参数隔离测试、RELEASE_APPEARANCE_OK、SETTINGS_ENTRY_RESET_OK。第一轮构建发现入口重置类型与旧迁移共处一个文件，已独立保留后重新完整构建通过。

主力机安装并启动本地1.12.0 Build186，正式发布的Build185保留在dist/retired/TaskDock-build185-before-cleanup.app。GitHub仍为1.12.0 Build185，本轮未发布。
