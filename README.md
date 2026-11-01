# PUBO iPhone 原生 App

独立 SwiftUI 客户端，iOS 17+，连接 `https://bolubo.com`。不依赖 Miria，不使用网页壳承载核心界面。

## 当前状态

当前开发候选 **0.2.0/build 18**，主要社交功能与默认关闭的原生推送正在重新验收。上次完整交付为 build 15：顶部标签和更多合并为连续圆角卡片。保留 SwiftUI 原生四页导航，公告、韩国女团榜单、帖子流排列；底部“我的”显示头像，白色发帖入口悬浮在导航上方，下拉、前台及实时刷新保持。

首次恢复账号、读取公告、榜单和帖子时显示适配浅深色的扫光骨架屏。数据到达立即显示；刷新保留旧内容，失败提供重试，减少动态效果时静态展示。不会为了动画人为延迟生产请求。

[界面回归](https://github.com/qianshou330-cyber/pubo-ios/actions/runs/41328458094)的21项核心、5项包校验、两个尺寸各22项UI全部通过，共70项。随后发现目标层构建号仍为13，仅修正为14；[独立打包验收](https://github.com/qianshou330-cyber/pubo-ios/actions/runs/41331898485)先确认App/核心/测试/脚本源码未变，再完成Xcode26.0.1下两类Release及 **iPhoneOS / arm64未签名IPA**。97张实际截图和加载录像已导出。旧UI工作流因构建号核验失败而整体为失败，不能混称整轮成功；联合证据见 [验收记录](docs/STATUS.md) 和 [结构化证据](docs/evidence/home-validation.json)。

设备文件：`PUBO-0.2.0-14-iphoneos-arm64-unsigned.ipa`，Actions 的 `pubo-iphone-unsigned-7de4eec6090e55aec7b2ccd576a03780574aca7d-attempt-1` 产物保留7天，交付目录另有持久保存。**需要签名才能安装；尚未完成实体 iPhone 验收。** [构建和签名说明](docs/BUILD.md)。旧 0.1.2 包及历史验收保留。

**这不是可直接上架的版本。** 搜索、收藏、投票、自己的帖子删除、回复分页、资料图片及网盘选择、私信版本编辑／撤回／反应、重新授权入口已实现候选。原生 APNs 代码和追加迁移已实现，真实通道保持关闭；签名、真实设备、服务条款及发行资料仍待条件。功能与验收状态分开记录，见 [功能清单](docs/H5_PARITY.md)、[推送交接](docs/NATIVE_PUSH.md)。

build 17 的真实隔离后端联合验收已确认投票、私信编辑和撤回；发现搜索框缺失，反应测试未兼容服务端字符规范化。build 18 修复搜索入口、反应匹配，并加入编辑冲突、失联核对与实际撤销反应检查。新的整轮结果尚待云端，不沿用旧版本通过结论。

## 构建

在 macOS / Xcode 上：

```sh
brew install xcodegen
swift test
swift scripts/brand-assets.swift
xcodegen generate
python3 scripts/simulator-tests.py
```

GitHub Actions 使用标准 `macos-15` 和 Xcode 26.0.1，主流程65分钟、真实隔离后端流程60分钟超时，产物保留7天，无签名密钥。模拟器产物与未签名设备 IPA 分开保存；设备 IPA 也须完成签名才能安装。

## 隔离与安全

- 默认仅连接本站 HTTPS；令牌只放 Keychain，不保存密码。
- 私信附件通过本站私有接口访问，不使用公开网盘链接代替。
- 测试使用合成数据；不向生产发送短信、帖子或私信。
- 服务器、Android、旧 iOS 壳工程、Bot 与榜单均不属于修改范围。

首版提供 App 内通知，不包含 APNs 锁屏推送。隐私政策已发布至 https://bolubo.com/privacy.html；服务条款、签名、TestFlight 和真实设备仍须在分发前完成。

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
