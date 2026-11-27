# PUBO iOS 上架前交接清单（供外包签名与 TestFlight / App Store 提审团队）

> 本文件仅含公开技术规格、合规映射与真机验收步骤，**不含任何证书、私钥、开发者 Team ID、生产账号或私密数据**。

## 1. 交付产物规格（未签名 Release 设备包）

- **包名规范**：`PUBO-0.10.0-148-iphoneos-arm64-unsigned.ipa`（来自正式 `package` 作业的 `four-tabs-iphone-unsigned-<commit>`，勿使用带 `QA-INCOMPLETE` 的候选包）
- **Bundle Identifier**：`com.bolubo.native`
- **版本与构建号**：`0.10.0` / `148`（如外包团队重复上传 TestFlight，仅递增 `CFBundleVersion` 即可）
- **架构与平台**：真机 `iPhoneOS` thin `arm64` Mach-O（`UIDeviceFamily = [1]` 仅 iPhone，`MinimumOSVersion = 17.0`）
- **URL Scheme**：`pubonative`（`com.bolubo.native.auth`，用于站内网页授权回跳）
- **出口加密合规**：`ITSAppUsesNonExemptEncryption = false`（仅使用系统标准 HTTPS/TLS，无需额外加密备案）
- **App Transport Security**：无放宽例外，仅请求 `https://bolubo.com`
- **Release 洁净度守卫（`scripts/package-device.py` 自动强检）**：
  - 0 处测试夹具代码（`FixtureTransport`、`--ui-testing`、`systemUptime`、`misskey-hub.net` 均已从 Release 二进制清零）
  - 0 个测试/对齐素材（`NotificationVisualCases.json`、`TimelineVisualCases.json`、`ChatParity.json`、`TimelineParity.json`、`PublicPosterRedFixture.mp4` 均不打入 Release 包）
  - 保留开源许可声明：`SDWebImage-LICENSE.txt`、`Tabler-LICENSE.txt`
  - 内置 1024×1024 不透明 `AppIcon`（无 Alpha 通道）

## 2. 重签与 Capabilities 注意事项

1. **常规 TestFlight / App Store 重签**：
   - 使用与 `com.bolubo.native`（或外包目标 Bundle ID）匹配的 Apple Distribution 证书与 App Store Provisioning Profile 对 `Payload/PUBO.app` 重签并打包上传。
   - 如更换 Bundle ID，须同步更新 `Info.plist` 中的 `CFBundleIdentifier` 与服务端 APNs（如启用）配置。
2. **推送能力（`aps-environment`）**：
   - 包内 `Info.plist` 声明 `PUBOAPNSEnvironment = production`，工程 entitlements 为 `aps-environment = production`。
   - 当前后端默认 `nativePush.enabled = false`（详见 `docs/NATIVE_PUSH.md`），App 内实时消息与通知不受影响；若首版暂不开通锁屏推送，可不勾选 Push Notifications 或保持默认关闭状态；若需开通，须先在服务端配置对应 Team ID / Key ID / `.p8` 私钥并在真机完成锁屏投递验收。

## 3. App Store Connect 隐私标签与权限说明映射

- **隐私清单**：已内置 `Payload/PUBO.app/PrivacyInfo.xcprivacy`（`NSPrivacyTracking = false`，`NSPrivacyAccessedAPICategoryUserDefaults = CA92.1`）及 `SDWebImage_SDWebImage.bundle/PrivacyInfo.xcprivacy`（`NSPrivacyAccessedAPICategoryFileTimestamp = C617.1`）。
- **App Store 隐私问卷收集项（全部仅用于 App Functionality，不用于跨 App 追踪）**：
  - 联系信息：姓名/昵称、邮箱、手机号（注册与账号安全）
  - 标识符：用户 ID、设备安装 ID（仅用于推送订阅标识）
  - 用户内容：照片/视频、语音音频、消息内容、其他用户发帖内容、举报/客服反馈内容
- **系统权限提示文案（已在 `Info.plist` 配置）**：
  - `NSCameraUsageDescription`：扫描用户二维码，或拍摄你主动用于发帖和私信的照片、视频。
  - `NSMicrophoneUsageDescription`：录制你主动发送的私信语音。
  - `NSPhotoLibraryAddUsageDescription`：将你选择的图片保存到相册。
- **App Review 重点合规核查点（建议写入审阅备注）**：
  - **Guideline 1.2（UGC 社区内容安全）**：注册前强制逐项阅读并同意服务器规则、服务条款/隐私政策及社区安全注意事项；帖子、聊天、个人主页均提供**举报**（`users/report-abuse`）与**屏蔽拉黑**（`blocking/create`）入口。
  - **Guideline 5.1.1(v)（账号删除）**：已提供 App 内原生永久注销入口（我的 → 设置 → 账号 → 删除账号，走 `i/delete-account`）。
  - **隐私政策 URL**：`https://bolubo.com/privacy.html`（并在站内配置 `tosUrl` 后同步显示服务条款）。
  - **审阅演示账号**：提审 App Store 前请准备一个可用的演示测试账号写入 App Store Connect Review Notes（切勿写入本仓库）。

## 4. TestFlight 上架后真机验收清单（放量前逐项勾选）

1. **安装与冷启动**：TestFlight 下载安装、主屏图标清晰无黑边、冷启动无闪烁或卡死；如保留 `iOS 17.0` 声明，须在 iOS 17 真机至少完整走通一次。
2. **账号与认证**：真实 `bolubo.com` 账号注册/短信验证码、密码登录、两步验证、退出登录与多账号切换隔离。
3. **隐私设置（弱网重点回归）**：限速/弱网打开「隐私与内容偏好」，确认加载完成瞬间开关 **0 跳动**，开关状态保存并重启 App 回读一致。
4. **世界圈体验**：连续滑动 50+ 条含图/GIF/视频的真实帖子（核查流畅度与发热），点击正文准确进详情不误跳个人主页，核查真实视频首帧加载与播放。
5. **发帖与媒体**：相册选图/视频上传、相机现场拍照/录像（含拒绝权限后引导系统设置恢复）、CW 内容警告发帖与草稿恢复。
6. **私信与群聊**：文本、表情、图片、**真机麦克风录音发送与播放**、编辑/撤回/引用、前后台切回 WebSocket 自动重连、图片保存到系统相册。
7. **扫码与社交**：实物二维码扫描（相机拒绝/允许/恢复）、用户名搜索、关注与关注申请收发。
8. **安全与覆盖升级**：实测举报/屏蔽入口、测试账号注销流程，以及新版本覆盖旧版本安装后登录态与本地草稿保留。
