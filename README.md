# PUBO iPhone 原生 App

独立 SwiftUI 客户端，iOS 17+，连接 `https://bolubo.com`。不依赖 Miria，不使用网页壳承载核心界面。

## 当前实现

0.9.2 / build128 私信与群聊对齐已交付：混合最近会话、顶部搜索页签、群消息举报、参与者反应及消息动画。验收与保留差异见 [CHAT_ALIGNMENT.md](docs/CHAT_ALIGNMENT.md)，未签名包与同型号对照证据随交付提供。

0.9.1 登录注册静态版说明见 [AUTHENTICATION.md](docs/AUTHENTICATION.md)：恢复静态欢迎页、居中弹窗、服务器驱动登录、注册预检、原生密码重置；保留安全网页授权。准确验收结果以同提交交付目录为准。

0.9.0 本地时间线对齐说明见 [LOCAL_TIMELINE.md](docs/LOCAL_TIMELINE.md)：首次默认本地、账号独立筛选、紧凑帖子、公共动画媒体、反应及实时新帖队列。准确构建号和验收结果以同提交交付目录为准，候选构建不等于验收通过。

私信 GIF 新版说明见 [PRIVATE_GIF.md](docs/PRIVATE_GIF.md)：会话内与放大预览支持动画，保留附件鉴权和受限缓存；最终测试记录随对应 IPA 交付。

基于已验收的0.2.0/build22，按五阶段补齐，继续保持“动态、通知、私信、我的”四页导航。完整整合候选为0.7.0；每次构建的准确build、提交、测试结果、IPA哈希及未验项以对应交付目录DELIVERY.md为准。

- 私信引用定位/历史同步、免打扰角标、受保护附件保存与图片浏览；榜单涨跌、筛选记忆、团体搜索与7天走势。
- 游客动态、自动滚动公告、资料/背景/徽章/装饰、基础MFM与原生链接、媒体说明、指定可见、本站发布和定时帖子。
- 原生联系人/群聊、通知分类/关注审批、网盘、频道/列表/天线/剪藏/图库、热门与表情/反应详情。
- PUBO多账号隔离、认证申请、隐私/静音/屏蔽、邮箱密码/动态验证码/会话、邀请/成就、数据任务/迁移、个人访问令牌和Webhook。
- 原生管理界面覆盖当前H5的125项相关接口；按服务器权限显示和执行，修改前核对最新状态，危险操作确认，不确定结果保留待核对。验证码挑战和通行密钥使用官方网页流程。

## 边界与验收

当前源码的覆盖表是[分阶段功能表](docs/PARITY_ROADMAP.md)与[后台接口/页面表](docs/ADMIN_COVERAGE.md)。原生界面实现不等于每项写操作均完成验收；完整证据随对应IPA交付。`docs/H5_PARITY.md`、`docs/FEATURES.md`、`docs/STATUS.md`及旧evidence记录的是build22历史基线，不覆盖新版结果。

Pages、Play、Deck、主题/插件/网页脚本及H5专属客户端设置从系统浏览器打开，并标注“网页版”。复杂动态MFM回到原帖网页版。游戏遵循网站关闭状态。原生主题与网页CSS互不影响。

帖子全文搜索和APNs保持服务器既有关闭策略，普通网页授权不预先请求管理员权限。管理和安全操作临时授权仅驻留内存，15分钟闲置或进入后台失效；认证材料仅受保护内存查看。

交付**未签名iPhoneOS arm64 IPA**，最低iOS17。必须另行签名才能安装；构建通过不代表安装、TestFlight或上架。真实iPhone、最低系统运行、相机/麦克风/相册授权、真实推送及实机覆盖升级仍需单独验收，不用模拟器结果代替。

本轮仅改独立iOS源码与隔离测试，不改生产H5、数据库/Redis、Cloudflare、中继、Bot、榜单调度、APK或游戏。旧包及未提交内容保留。

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
