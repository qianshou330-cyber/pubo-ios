# 构建、验收与签名交接

## 开发与模拟器

需要 macOS、Xcode 16 或更新版本、相应 iOS 模拟器运行时。部署目标为 iOS 17，实际最低系统设备验收另行记录。

```sh
brew install xcodegen
swift test
swift scripts/brand-assets.swift
xcodegen generate
python3 scripts/simulator-tests.py
xcodebuild -project PUBO.xcodeproj -scheme PUBO -configuration Release -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath build/release CODE_SIGNING_ALLOWED=NO build
```

`project.yml` 是工程事实来源。XcodeGen 生成 `PUBO.xcodeproj` 和 Info.plist；品牌脚本生成 1024px 不透明图标。不要提交 `.build`、`build`、用户工作区、证书、私钥或真实账号数据。

## GitHub Actions

目标公开仓库为 `qianshou330-cyber/pubo-ios`。`main` push、PR 和手动运行触发标准 `macos-15`，单次 45 分钟超时，产物保留 7 天，无签名 secrets，无付费 runner。并发更新取消旧构建。工作流执行 core 单测、两个不同尺寸 iPhone 的 UI 测试、Release 模拟器构建并保留 xcresult、截图和 `.app`。

所有 UI 测试通过 **Debug 专用** `--ui-testing` 启用合成 transport，不请求生产 API、头像、WebSocket。Release 忽略此开关。可以在 Xcode Scheme 添加 `--logged-out`、`--dark`、`--large-text`、`--slow`、`--network-error`、`--reply-required`、`--lost-chat-response`、`--lost-post-response` 验证指定情形。

报告中的 `swiftc -frontend -parse` 只表示语法检查；Linux `swift test` 只覆盖 PUBOCore。两者都不能代替 Xcode 编译、模拟器界面检查或实体 iPhone 验收。

## HTTP 契约复核

`scripts/check-contracts.py` 用只读本站源码及 OpenAPI 检查请求字段、私密附件和流式认证。隔离 HTTP 回执见 `docs/evidence/`。本轮在全新 Docker internal 网络、空数据库、合成短信服务和合成账号上验证实际 PUBO 后端，不使用生产库或生产令牌；容器和状态卷验收后清理。

独立 HTTP 驱动位于 `scripts/isolated/`。它只接受固定内部地址且要求全新 requireSetup 实例，不能更改为生产地址使用。测试需要与当前网站业务源码一致的后端构建；本 App 仓库不捆绑网站或数据库。

## 后续签名与安装

模拟器 `.app` **不能安装到实体 iPhone**。取得 Apple 开发者账号及签名条件后，在 Xcode 为应用选择开发团队，核对正式 Bundle ID，移除本机签名禁用覆盖，为真机 SDK 构建并按所选分发方式生成合法签名产物。签名信息仅放本机 Keychain 或受限 CI secrets，不进入仓库。

TestFlight/App Store 前须完成真机安装、相机/相册与麦克风授权、语音时长、文件保护、系统授权回调、移动网络/弱网、后台切换、退出后数据清理和最低 iOS 17 的测试。填写真实的 App 隐私披露，并提供有效隐私政策和服务条款；当前网站缺少有效地址，不能自行伪造。

## 故障排查

- 401/403：核对登录和服务器权限；必要时退出后重新登录。不要粘贴令牌到日志。
- 待发“不确定”：使用核对入口，不要创建新请求来重复发送；普通帖先查看自己的帖子。
- 非互关附件被拒绝：等待对方回复，客户端不修改规则。
- 图片显示短码：表情后台加载失败时仍可阅读和登录，重新进入后再加载。
- CI 无模拟器：安装可用 iPhone runtime；不要把未运行的测试标成通过。
- 生成/编译失败：保留 xcresult 和构建报错，修复后重跑该候选；不能凭 Linux 语法检查分发 App。

这轮不部署网站，不需要重启生产容器，也没有数据库回滚操作。
