# PUBO iPhone 原生 App

独立 SwiftUI 客户端，iOS 17+，连接 `https://bolubo.com`。不依赖 Miria，不使用网页壳承载核心界面。

## 本次交付

**0.2.0 / build 22** 已完成开发、自动化与真实隔离后端联合验收。保留“动态、通知、私信、我的”四页导航；首页为公告、韩国女团榜单、帖子流，顶部标签与“…”使用连续12pt圆角卡片，底部头像、白色悬浮发帖、骨架屏和下拉刷新保持。

新增帖子／用户／话题搜索、收藏及列表、投票展示／投票／创建、自己的帖子删除、回复分页、资料头像／背景图和网盘选择；补齐私信版本编辑、撤回、添加／取消反应、重连状态核对、授权不足时的重新授权入口。

- [完整云端验收](https://github.com/qianshou330-cyber/pubo-ios/actions/runs/41346292681)：27核心、6包校验、两个尺寸各28UI，共89项通过；模拟器和iPhoneOS Release构建通过。
- [原生连接真实隔离后端](https://github.com/qianshou330-cyber/pubo-ios/actions/runs/41346292715)：搜索收藏、投票、私信编辑／撤回／添加及取消反应三个场景通过，并核对服务器实际记录；生产API请求为0。
- 后端18单测、9推送API及17既有聊天回归通过。新推送能力已按默认关闭部署，仅追加设备订阅表；网页资源、9个非Web服务、11项榜单调度与游戏关闭状态保持。

设备文件：`PUBO-0.2.0-22-iphoneos-arm64-unsigned.ipa`，1,928,082字节，SHA-256 `01ff14158201fae97e0da74f9a241b070ced0191e272a48ad6da27e7b4d547a9`。它是**iPhoneOS／arm64未签名IPA**，不是模拟器包。需要签名后才能安装，尚未完成实体iPhone验收。旧包及失败候选证据保留。

## 功能边界

搜索遵循本站账号策略。正式站默认帖子全文搜索仍关闭、用户搜索开启；App明确提示权限，不擅自调整H5或账号规则。隔离验收只在独立空站开启测试搜索权限。

原生APNs登记、注销、隐私保护及点击后鉴权代码已完成，真实通道保持关闭。Apple开发者账号、签名、真实设备／锁屏投递、服务条款和发行资料仍待补齐，**不能直接宣称可以上架**。本次主要功能完成不代表H5所有模块均已移植；群聊、小游戏、管理员后台、多账号和完整MFM不在本轮。

功能与验证情况见[交付清单](docs/FEATURES.md)、[H5差距清单](docs/H5_PARITY.md)、[实际验收记录](docs/STATUS.md)和[结构化证据](docs/evidence/social-validation.json)。

## 构建

```sh
brew install xcodegen
swift test
python3 -m unittest discover -s scripts -p 'test_*.py' -v
swift scripts/brand-assets.swift
xcodegen generate
python3 scripts/simulator-tests.py
```

GitHub Actions使用标准`macos-15`、Xcode26.0.1，主流程65分钟、真实隔离后端流程60分钟超时，产物保留7天。未配置签名密钥或付费runner。设备IPA与模拟器证据分开保存；详见[构建与签名](docs/BUILD.md)、[推送交接](docs/NATIVE_PUSH.md)。

## 源码与数据边界

- `App/`：原生界面、账号、动态、发帖、通知及受保护私信。
- `Sources/PUBOCore/`：接口、错误、回执与待发状态；`Tests/`为核心测试。
- `UITests/`：合成界面回归与真实隔离后端联合场景。
- `scripts/isolated/`：固定隔离目标、空数据库、合成账号；不使用生产账号或生产数据。
- 登录令牌只保存在Keychain，密码不持久保存；私信附件使用本站受保护接口。

隐私政策为 https://bolubo.com/privacy.html；真实APNs开放前还须更新相应披露。源码采用AGPL-3.0-only，见`LICENSE`与`NOTICE.md`。
