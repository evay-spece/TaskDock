# TaskDock 小红书内测：7 天试用与人工发码

- 首次启动获得 7 天试用。
- 用户在 TaskDock 菜单栏选择“输入内测激活码…”，每个有效码增加 7 天；提前输入会从现有到期日继续增加。
- 每个码在同一安装中只能兑换一次。到期后，窗口操作会要求先输入新码。
- 内测码不绑定设备、不访问授权服务器。它可以转发到另一台 Mac 使用，无法远程撤销；适合小规模内测，不适合收费授权。

## 发码

在项目目录运行 `scripts/beta-code issue`，复制输出的整串 `TD7.` 激活码发给用户。每运行一次生成一个新码；无需预先建立码池。

发码私钥保存在主力机 `~/Library/Application Support/TaskDock/BetaCodes/issuer-private-key.pem`。它不在项目或 App 中，权限为仅当前用户可读。请单独备份；丢失后无法再生成与已发布 App 匹配的新码。项目 `Resources/TaskDockBetaPublicKey.pem` 是可公开的验码公钥，需要随 App 一起发布。

## 重新生成密钥

首次配置使用 `scripts/beta-code init`。已有私钥时命令会拒绝覆盖，因为覆盖会使旧版 App 无法验证新码。要轮换密钥，需要发新版 App，不能只替换主力机的发码文件。
