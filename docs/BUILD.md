# 构建、验收与签名交接

## 开发与模拟器

需要 macOS、Xcode 26 系列及 iOS26 SDK（当前云端为26.0.1）、相应 iOS 模拟器运行时。部署目标为 iOS 17，实际最低系统设备验收另行记录。

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

目标公开仓库为 `qianshou330-cyber/pubo-ios`。`main` push、PR 和手动运行触发标准 `macos-15`，主流程65分钟、联合验收流程60分钟超时，产物保留 7 天，无签名 secrets，无付费 runner。并发更新取消旧构建。工作流执行 core 单测、6 项设备包校验单测、两个不同尺寸 iPhone 的 UI 测试、Release 模拟器回归，以及独立的 **iPhoneOS 真机 Release 构建和未签名 IPA 封装**。

两个产物独立：`ios-validation-<commit>` 保存测试、截图和模拟器 `.app`；`pubo-iphone-unsigned-<commit>` 保存设备 `.ipa` 和 `device-package.json`。请勿将前者改扩展名充当真机包。

历史 0.1.1 完整工作流 run41306913120 的测试、两类构建与封装均通过，但设备包上传服务超时。恢复工作流 `device-recovery.yml` 只固定构建已验证的 `6707a090e3065f95cb117606f9d8c93d26dba0d9`，run41309035703 已成功上传；支持手动运行及专用恢复分支触发，15 分钟超时。它不是后续版本的默认构建入口；日常改动仍使用 `ios.yml` 完整验收。

合成界面回归通过 **Debug 专用** `--ui-testing` 启用合成 transport，不请求生产 API、头像、WebSocket。Release 忽略此开关。可以在 Xcode Scheme 添加 `--logged-out`、`--dark`、`--large-text`、`--slow`、`--network-error`、`--reply-required`、`--lost-chat-response`、`--lost-post-response` 验证指定情形。

报告中的 `swiftc -frontend -parse` 只表示语法检查；Linux `swift test` 只覆盖 PUBOCore。两者都不能代替 Xcode 编译、模拟器界面检查或实体 iPhone 验收。

## HTTP 契约复核

`scripts/check-contracts.py` 用只读本站源码及 OpenAPI 检查请求字段、私密附件和流式认证。隔离 HTTP 回执见 `docs/evidence/`。本轮在全新 Docker internal 网络、空数据库、合成短信服务和合成账号上验证实际 PUBO 后端，不使用生产库或生产令牌；容器和状态卷验收后清理。

独立 HTTP 驱动位于 `scripts/isolated/`。它只接受固定内部地址且要求全新 requireSetup 实例，不能更改为生产地址使用。测试需要与当前网站业务源码一致的后端构建；本 App 仓库不捆绑网站或数据库。

## 后续签名与安装

本次可交付 **未签名的真机 IPA**。生成方式（先执行前述品牌和工程生成步骤）：

```sh
python3 -m unittest discover -s scripts -p 'test_*.py' -v
xcodebuild -project PUBO.xcodeproj -scheme PUBO -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build/device ARCHS=arm64 ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' build
python3 scripts/package-device.py
```

输出 `build/unsigned/PUBO-0.2.0-<build>-iphoneos-arm64-unsigned.ipa`，结构为 `Payload/PUBO.app`。校验脚本同时核对 Info.plist 的 iPhoneOS、二进制 Mach-O 的 iOS 平台值 2（拒绝值 7 的 arm64 模拟器）、arm64 架构、可执行权限、无代码签名/描述文件、ZIP 内容一致和 SHA-256。重复执行拒绝覆盖同名 IPA，需使用新的构建目录或先归档原产物。打包脚本从project.yml读取并核对工程与目标版本；版本冲突拒绝打包。

**未签名 IPA 不能直接安装到普通 iPhone。** 它是后续签名输入，不是已安装验收或 App Store 分发成品。应以 Apple 开发者签名证书、与 Bundle ID 匹配的描述文件及适用设备/分发方式签名；注册测试设备后可按开发或 Ad Hoc 方式安装。详见 [Apple 设备分发说明](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices)。不使用他人证书或未经核实的付费签名服务。

若从源码在 Xcode 签名构建，在本机配置中覆盖项目的 `CODE_SIGNING_ALLOWED=NO`，选择自己的开发团队及合法标识；不要把签名禁用的原构建命令照搬到签名步骤。签名资料只保存在本机 Keychain 或受限配置，不进入源码、公开日志或交接。模拟器 `.app` 始终不能改包替代设备构建。

TestFlight/App Store 前须完成真机安装、相机/相册与麦克风授权、语音时长、文件保护、系统授权回调、移动网络/弱网、后台切换、退出后数据清理和最低 iOS 17 的测试。填写真实的 App 隐私披露，并提供有效隐私政策和服务条款；隐私政策已发布为 https://bolubo.com/privacy.html；服务条款及完整隐私披露仍待完成。

## 故障排查

- 401/403：核对登录和服务器权限；必要时退出后重新登录。不要粘贴令牌到日志。
- 待发“不确定”：使用核对入口，不要创建新请求来重复发送；普通帖先查看自己的帖子。
- 非互关附件被拒绝：等待对方回复，客户端不修改规则。
- 图片显示短码：表情后台加载失败时仍可阅读和登录，重新进入后再加载。
- CI 无模拟器：安装可用 iPhone runtime；不要把未运行的测试标成通过。
- 生成/编译失败：保留 xcresult 和构建报错，修复后重跑该候选；不能凭 Linux 语法检查分发 App。

当前推送扩展增加默认关闭的独立原生推送能力和设备订阅表；发布只替换经过核验的后端，网页静态资源保持。故障关闭新能力或回退应用镜像，绝不恢复旧数据库覆盖业务记录。

首页测试另支持 Debug 参数 `--slow-startup`、`--skeleton-loading`、`--skeleton-failure`、`--reduce-motion`、`--refreshable-feed`；生产 Release 不启用合成延迟或数据。

本次目标构建号修正使用 `home-package.yml`，固定核验App/核心/测试/scripts与已通过70项测试的 `33e93dbe0a608dde3dfb75ed625e2f2b031d4938` 一致，project.yml仅改目标号13→14，再重新编译两类Release。该恢复流程仅适用于这份已验收源码；后续功能改动仍须运行完整ios.yml。

当前build22同时执行native-integration.yml：Debug专用固定回环地址连接真实隔离后端，先验证普通账号搜索权限和样本，再从App执行搜索收藏、投票及完整私信操作，核对实际服务器记录。Release没有该测试地址或ATS例外。
