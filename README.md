# PUBO iPhone 原生 App

独立 SwiftUI 客户端，iOS 17+，连接 `https://bolubo.com`。不依赖 Miria，不使用网页壳承载核心界面。

## 当前状态

原生源码和标准 macOS 云端构建已接通。已实际完成 Xcode 编译、两个 iPhone 尺寸的模拟器测试及 Release 模拟器构建；最终产物复核状态与测试边界见 `docs/STATUS.md`。尚未签名或进行真机验收，不能直接安装到 iPhone。

## 构建

在 macOS / Xcode 上：

```sh
brew install xcodegen
swift test
swift scripts/brand-assets.swift
xcodegen generate
python3 scripts/simulator-tests.py
```

GitHub Actions 使用标准 `macos-15`，45 分钟超时，产物保留 7 天，无签名密钥。模拟器 `.app` 不能直接安装到 iPhone。

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

代码以 AGPL-3.0-only 提供，见 `LICENSE` 与 `NOTICE.md`。
