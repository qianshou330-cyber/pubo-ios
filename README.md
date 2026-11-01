# PUBO iPhone 原生 App

独立 SwiftUI 客户端，iOS 17+，连接 `https://bolubo.com`。不依赖 Miria，不使用网页壳承载核心界面。

## 当前状态

正在开发 **0.2.0/build 8 候选**：紧凑首页、公告和榜单读取、主要社交功能与原生推送。新候选尚未完成云端及整体验收；下面的 0.1.2 是保留的上一版验证记录，不代表 0.2.0 已通过。APNs 保持关闭，签名和真机验收仍待开发者账号。

当前版本 **0.1.2/build 7**。保持 SwiftUI 原生实现，已同步 PUBO 配色、首页/注册/登录、私信和发帖界面。发帖入口使用普通铅笔；编辑页为顶部取消/头像/可见范围/更多/白底黑字发帖按钮、连续正文与图标工具栏，支持 CW 和简单预览。保留四个原生主页面，入口仍位于动态页顶部。

[本次完整云端验收](https://github.com/qianshou330-cyber/pubo-ios/actions/runs/41314836776)成功：18 项核心测试、5 项设备包校验测试、两台 iPhone 各 16 项 UI 测试，模拟器 Release 回归、**iPhoneOS / arm64 Release 编译与未签名 IPA**均通过；74 张实际截图导出，新发帖状态已复核。详细记录见 [STATUS.md](docs/STATUS.md) 和 [结构化证据](docs/evidence/composer-validation.json)。

设备文件：`PUBO-0.1.2-7-iphoneos-arm64-unsigned.ipa`，位于该次 Actions 的 `pubo-iphone-unsigned-a55681eac47fbdd6be5dbd67b41a97f85699a64e` 产物中（如重试上传则带 retry 前缀），保留 7 天；交付目录另有持久保存。**这是真机 SDK 编译的未签名包，需签名后才能安装到 iPhone；尚未进行实体设备运行验收。** 构建及签名交接见 [BUILD.md](docs/BUILD.md)。

**没有 H5 全部功能。** [功能自查清单](docs/H5_PARITY.md)逐项列出已有、部分、网页依赖与缺失能力。网盘管理、投票、私信编辑撤回/反应、群聊、完整搜索/资料/安全设置、榜单游戏及后台等仍存在差距；视觉同步不代表这些功能已原生完成。

## 构建

在 macOS / Xcode 上：

```sh
brew install xcodegen
swift test
swift scripts/brand-assets.swift
xcodegen generate
python3 scripts/simulator-tests.py
```

GitHub Actions 使用标准 `macos-15`，45 分钟超时，产物保留 7 天，无签名密钥。模拟器产物与未签名设备 IPA 分开保存；设备 IPA 也须完成签名才能安装。

## 隔离与安全

- 默认仅连接本站 HTTPS；令牌只放 Keychain，不保存密码。
- 私信附件通过本站私有接口访问，不使用公开网盘链接代替。
- 测试使用合成数据；不向生产发送短信、帖子或私信。
- 服务器、Android、旧 iOS 壳工程、Bot 与榜单均不属于修改范围。

首版提供 App 内通知，不包含 APNs 锁屏推送。签名、TestFlight、真实设备、政策页面将在分发前单独验收。

## 源码与验证入口

- `App/`：四个原生主页面、注册登录、发帖、个人设置及受保护私信。
- `Sources/PUBOCore/`：本站接口、错误处理、发送回执和私信待发状态。
- `Tests/`：可在 macOS 或 Linux Swift 运行的核心测试。
- `UITests/`：隔离合成数据的 iPhone 界面测试，覆盖登录导航、CW、弱网、私信及不确定发送。
- `docs/BUILD.md`：构建、测试与签名交接。
- `docs/ARCHITECTURE.md`：接口及本机数据边界。
- `docs/STATUS.md`：实际结果与剩余验收项。
- `docs/H5_PARITY.md`：H5 功能差距清单。

代码以 AGPL-3.0-only 提供，见 `LICENSE` 与 `NOTICE.md`。
