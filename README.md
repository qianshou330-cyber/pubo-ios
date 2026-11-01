# PUBO iPhone 原生 App

独立 SwiftUI 客户端，iOS 17+，连接 `https://bolubo.com`。不依赖 Miria，不使用网页壳承载核心界面。

## 当前状态

正在验收 **0.1.2/build 3** 发帖界面对齐候选：入口铅笔、顶部头像/可见范围/发帖、连续编辑区与图标工具栏。以下 0.1.1 设备包为已完成的上一阶段证据，不能代替新候选验收。

当前版本 **0.1.1 / build 2**，已完成网页风格、首页/注册/登录原生交互同步；浅深主题正常字号一致，辅助功能大字体单独适配。

[本次精确构建](https://github.com/qianshou330-cyber/pubo-ios/actions/runs/41306913120)：18 项核心测试、5 项设备包校验测试、两个 iPhone 尺寸各 14 项界面测试、Release 模拟器回归及 **iPhoneOS / arm64 真机 Release 编译**通过，60 张截图已导出复核。

原完整工作流最后仅因 IPA 产物上传超时显示失败；测试和编译均已通过。[设备包恢复构建](https://github.com/qianshou330-cyber/pubo-ios/actions/runs/41309035703)固定检出同一份已验证源码 `6707a090e3065f95cb117606f9d8c93d26dba0d9`，重新编译、封装及上传全部成功。两次运行和实际下载校验分别留有证据，没有将原工作流标为全绿。

设备产物：`PUBO-0.1.1-2-iphoneos-arm64-unsigned.ipa`，**未签名，需签名后才能安装到 iPhone**。上述恢复构建的 `pubo-iphone-unsigned-6707a090e3065f95cb117606f9d8c93d26dba0d9` 产物中可下载，保留 7 天；已另在交付目录持久保存。构建/核验/签名交接见 [BUILD.md](docs/BUILD.md)。它不是模拟器包，也不代表真机运行已通过。

**没有 H5 全部功能。** [功能自查清单](docs/H5_PARITY.md) 明确首页公告/访客流、搜索收藏投票、私信编辑撤回/反应、群聊、完整网盘/资料/安全设置、榜单游戏及后台等差距。详细验收和剩余项见 [STATUS.md](docs/STATUS.md)。

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
