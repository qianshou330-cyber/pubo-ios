# 开发验收记录

## 2026-11-01 工程建立

- 创建独立 Swift Package 核心层、SwiftUI 工程描述、模拟器测试和 macOS 工作流。
- 核对本站私信附件路由为 `/api/chat/attachments/:id/original`，要求 Authorization Bearer，不接受 URL 查询令牌。
- 核对聊天发送使用 `attachmentIds` 与 `clientMessageId`；普通发帖接口未提供相同幂等契约。
- GitHub 仓库尚待创建：连接不提供建仓库操作，浏览器与桌面工具初始化失败；已请求用户创建公开仓库并授予现有连接访问。
- Xcode、模拟器、签名和真机验收尚未执行。未修改生产服务。

## 2026-11-01 本地实现与隔离接口验收

- 完成原生四页导航、短信注册与 signin-flow/TOTP、Keychain 会话、三类时间线、详情、发帖/回复/转发、图片视频附件、CW/敏感媒体、本站表情、反应、通知、个人主页、关注/屏蔽/举报、基本资料、聊天隐私及删除入口源码。
- 完成本地受保护草稿、公开缓存上限、前台 WSS 订阅、后台断开、退避重连及按 ID 合并。私信稳定 clientMessageId、发送前落盘、手动对账、首条业务提示、保护附件、语音、引用、置顶/免打扰均已接入。
- **18 项 PUBOCore XCTest 通过**：Swift 6.0.3 Linux，覆盖凭据范围、错误映射、限流、失败不自动重发、有序附件、作者/收件人/引用、发帖回执、重启待发和去重。日志见 `evidence/swift-core-linux.log`。
- **11 项只读契约检查通过**：实际网站源码与兼容 OpenAPI，见 `evidence/static-contract.json`。
- 全部 App/UITests Swift 语法检查通过，StreamClient 与 FixtureTransport 在 Foundation 环境的类型检查通过；SwiftUI、UIKit 与 AVFoundation 仍未经过 Xcode 类型检查。
- **隔离 HTTP 62 项断言通过，6 组场景、44 次 API 请求**：实际后端，合成账号和短信提供方，无外网；首条并发只成功一条，已读不解锁，回复解锁、附件 Bearer 下载及无关管理员拒绝等通过。见 `evidence/http-contract.json`。
- 隔离后端来源与当前正式业务源码比对一致，使用现成编译包构造本地测试镜像；并非生产部署或精确生产镜像重新发布。空库迁移只发生在本轮全新测试库，6 个测试容器及状态卷已清理。
- 测试修复了 `signin-flow` 路由、空 `fileIds` 被拒绝、私信正文规范化、sinceDate 整数毫秒、会话置顶单独分页、通知 CW 遮蔽等适配问题。早期失败与修正回执保留在独立本地验收目录。

## 当前验收状态

| 项目 | 实际状态 |
|---|---|
| GitHub 仓库及源码上传 | PASS；公开仓库 main，源码和工作流已上传 |
| Xcode Debug / Release 编译 | PASS；Xcode 16.4 / Swift 6.1.2，实际产物确认 0.1.0/build 1/仅 iPhone |
| 两个 iPhone 尺寸模拟器启动及 9 项 UI 测试 | PASS；SE 第三代、16 Pro Max 各 9 项，iOS 18.5；包含每个输入前缀及发送失败后草稿正文精确检查 |
| 深浅主题、大字体、键盘、弱网、CW 界面截图 | 已导出并检查 12 张；模拟网络失败与慢表情通过；不是运营商弱网实测 |
| App 本身端到端连接隔离后端 | NOT_RUN；当前 HTTP 验收验证接口契约，尚未在模拟器中操作原生 App |
| 原生授权网页回调、Keychain 与文件保护真机行为 | NOT_VERIFIED_ON_DEVICE |
| 签名、实体安装、相机/麦克风及 TestFlight | OUT_OF_THIS_DELIVERY_UNTIL_SIGNING_READY |
| 有效隐私政策、服务条款、App 隐私披露 | REQUIRED_BEFORE_DISTRIBUTION；现站点地址不完整 |

当前交付仍是源码与模拟器产物，没有签名 IPA。最低 iOS 17、真机行为、网页授权回调和原生 App 与隔离后端联合端到端仍待验证；独立 HTTP 契约测试与模拟器合成数据测试不能互相替代。

## 2026-11-01 仓库创建完成

修复控制工具运行实例引用的临时目录缺失后，外部 Chrome 控制恢复。已在用户登录的 GitHub 创建公开仓库 <https://github.com/qianshou330-cyber/pubo-ios>，默认分支 main，初始化 README。未改动浏览器登录、凭据或安全设置，未开通付费服务。

## 2026-11-01 云端构建与产物复核

- [run 41299212788](https://github.com/qianshou330-cyber/pubo-ios/actions/runs/41299212788) 的 18 项核心测试、两个尺寸各 9 项 UI 测试及 Release 模拟器编译实际通过。
- 首两轮构建中发现并修复图标绘图格式与 XCTest 退出按钮定位问题；保留失败记录，没有将失败阶段标为通过。
- 视觉复核发现快速批量自动输入的草稿文字不完整，补充逐键输入、每个前缀及发送前后完整正文断言，两个尺寸均通过。App 代码未据此修改；此证据证明受控键盘输入及失败保留，不代表所有真机输入法已验收。
- 实际产物核对发现 XcodeGen 的目标默认值覆盖全局版本/设备设置；已改为目标层明确 0.1.0/build 1/仅 iPhone，并校验生成的 Info.plist，最终候选通过；旧产物保留为阶段证据。
- 大字体下系统导航标题和收件范围菜单的长文字可能省略，页面可滚动，收件规则下方另有完整说明；不宣称完成全面辅助功能审计。

## 最终云端候选

[run 41300490345](https://github.com/qianshou330-cyber/pubo-ios/actions/runs/41300490345)，构建提交 `a8096b6d72ddb384ad0c87d0b39dc365e201d81a`：18 项核心测试、SE 第三代及 16 Pro Max 各 9 项界面测试、Release 编译及实际产物信息全部通过。原始 12 张模拟器截图已导出并复核，两种尺寸的草稿正文均完整保留。结构化结果见 `evidence/cloud-validation.json`。

本轮源码、构建流程、日志、截图和模拟器产物已交付。尚未验证项目仍按上表保留，不能将本结果当作签名安装、真机全面验收或 App Store 上架完成。最后的文档提交不改变已通过测试的 App、核心、测试或工作流代码。
