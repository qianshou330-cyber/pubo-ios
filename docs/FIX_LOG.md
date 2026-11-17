# 修复日志

按最新记录在前追加。此规范根据项目要求建立；以下仅补录可核实的最近 C60/C61，**不是全部历史修复清单**。旧记录不足时写“未核实”，不补造结果。

## 记录模板
```text
### YYYY-MM-DD / 候选编号 / 简短标题
状态：诊断中 / 修复待验证 / 部分验证 / 已验证（注明范围）/ 回退
代码版本或提交：
问题与复现/证据：
原因：已确认事实；待验证假设分开说明
修改内容：
涉及文件：
测试：命令或 CI 链接；通过 / 失败 / 未运行与阻塞
未解决事项、限制及下一步：
后续验证记录：时间、版本、新结果；保留前述历史
```

## 2026-11-17 18:45 UTC / C61 OCR 基线环境漂移复放
状态：诊断已验证（限 Linux 基线复放）；尚无安全修复，当前 macOS OCR 失败保留。
代码版本：55351e1922a1141ddc3eecd7e720f853bc4b232f；开始/提交前分支头 5b54361，无活动 CI。
问题：C61 固定 189 样本中的三个既有正样本，文本正确但置信度不足 80。
已确认：
- 语料元数据的原始基线是 Linux Tesseract 5.5.0 / Leptonica 1.84.1；CI 为 macOS Tesseract 5.5.3 / Leptonica 1.87.0。两边 English model SHA256 均为 7d4322bd2a7749724879683fc3912cb542f19906c83bcc1a52132556427170b2。输入 PNG SHA 均核验。
- 本次在原基线版本的本地 Linux 对全部 189 个原样本直接复放，不缩放/修图、不传入期望值，使用 psm7、完整 TSV、原 decode_tsv 和 80 门槛。189/189 接受/拒绝决策与保存的基线一致，67 个接受；普通负样本误接受 0。原有 4 个已知裁剪误接受仍存在，不算负样本通过。
- 三个争议样本本地重现基线置信度：3x10pt 1 = 85.269997；3x10pt 99plus = 83.686485；3x12pt 5 = 95.367226。对应 CI 为 78.208992 / 55.412251 / 74.187180。
- CI 相对基线还新增接受 3 个正确正样本（Bold-2x10pt-5、Bold-2x12pt-4、Regular-3x12pt-9），并拒绝 1 个原来已知的裁剪误接受。因此并非仅三个文件损坏；变化与 OCR 执行环境相关，不能简单以全局置信度偏移解释。
原因边界：已证明输入/模型相同而不同 OCR 栈的决策漂移；尚未隔离引擎版本、Leptonica、编译选项、SIMD 或平台各自的因果贡献。不能把相关性宣称为已锁定单一根因。
修改：仅本诊断记录与交接，无产品/OCR 代码、语料标签、模型/引擎 pin、几何防护或阈值修改。
涉及文件：docs/FIX_LOG.md、docs/AGENT_HANDOFF.md。
测试限制：上述直接执行旧引擎仅作离线对照，没有运行或绕过生产 engine_identity；不得称当前固定 5.5.3 验收通过。本地无 macOS/Xcode，且无 CMake/Leptonica 开发依赖，未执行同平台双版本编译对照；未安装新工具链。
下一步：先在隔离环境建立同平台 5.5.0/5.5.3 × 固定模型/完整 189 样本的对照，记录真实 binary、库与 SIMD 身份；或在现有固定 macOS 栈测试统一、答案无关的数值路径。任何候选都必须保持全部既有正样本与负样本保护、80 门槛和三阶段截图几何验证。不得回退引擎、调低阈值、挑样本或改预期标签来消除红灯。本轮不盲目重跑完整 UI。

## 2026-11-17 18:00 UTC / C61 候选包上传恢复及 OCR 证据复核
状态：仅上传恢复已验证；整体 QA 仍不完整，无产品修复或验收完成声明。
代码版本：55351e1922a1141ddc3eecd7e720f853bc4b232f。
行动/原因：针对原产物服务超时，仅重跑 candidate-package；新 job 134235071422 于 17:47:33 UTC 成功完成，未重跑其余 UI。
产物：[QA-INCOMPLETE artifact 14352744864](https://github.com/qianshou330-cyber/pubo-ios/actions/runs/44117699042/artifacts/14352744864)；归档 5545059 字节，SHA256 ac535d489837d64da27ce4bbd64ebbdf1db9de328d39cf8da53cd2fa6832c55f。
已下载核实：IPA 5581258 字节，SHA256 6f9ec9d7761bd291d5b31d3498dab8737c14f2e85dbe14eb084bce9c5492edf9；ZIP 完整性通过；Info.plist 标记 iPhoneOS、build148、最低 iOS17。同包 device-package.json 标记 arm64/iOS/UNSIGNED/PASS；candidate-status.json 明确 overallQA=INCOMPLETE。未做签名安装或真机测试。下载核实不等于已交付用户。
只读 OCR 排查：下载 C61 原始报告，3 个失败样本的文本分别正确读为 1、99+、5，但置信度为 78.208992、55.412251、74.187180，低于未变的 80 门槛。因此拒绝来自置信度，不是文本不匹配。此证据不支持降低门槛或将正样本改成预期拒绝。
涉及文件：仅 FIX_LOG.md、AGENT_HANDOFF.md 文档更新，无源码改动。
剩余事项：保留前述 UI 初始化、快照、预算与 OCR 失败。后续 OCR 方案需保持独立像素读取、固定模型和完整 189 样本控制，不能按预期答案修正输出；剩余 UI 原因仍待验证。当前查询无活动/排队作业。

## 2026-11-17 17:35 UTC / C61 后续验证与候选包重跑
状态：原轮结束失败；仅重跑候选打包，未完成交付。
代码仍为 [55351e1](https://github.com/qianshou330-cyber/pubo-ios/commit/55351e1922a1141ddc3eecd7e720f853bc4b232f)，后续交接/日志提交只改文档。
验证：已确认原轮所有作业结束，且测试分支无运行/排队作业，再通过单作业重跑接口重跑 candidate-package。原 job 134162066990；新 job 134235071422 已运行，仍属 [run 44117699042](https://github.com/qianshou330-cyber/pubo-ios/actions/runs/44117699042)。这不是重跑所有失败测试，也不是修复 App 源码。
原轮最终有效通过：核心检查、H5 参考；大小屏聊天布局各 5/5、大小屏聊天操作各 5/5、小屏页面状态 4/4、大屏旧回归 5/5、小屏视频 4/4。上述计数均核对原始日志和成功进程结束。
原轮失败分类：
- 小屏旧回归、小屏导航、大屏视频、大屏页面状态：Accessibility 初始化超时，未进入功能场景。
- 小屏输入区：模拟器恢复时终止服务命令 30 秒超时，未进入场景。
- 大屏输入区：testmanagerd 快照获取超时，后续触及原有 1800 秒预算。
- 大屏导航：最后一项仍进行时触及原有 2700 秒导航预算，未取得完整成功结果；不可混称 1800 秒。
- OCR：仍为上述 3 个固定正样本回归。
- 候选包：Release 编译完成，上传服务 5 次超时。验收 package 跳过。
涉及文件：本次仅更新 FIX_LOG.md 与 AGENT_HANDOFF.md；纯文档 skip ci，不取消重跑。
下一步：检查新候选包上传结果，若成功仍标 QA-incomplete，不冒充全量验收；保留失败证据，继续查环境/快照/门槛内执行时间及 OCR。未扩大超时、跳过断言或修改产品。

## 2026-11-17 / C61 / 就绪诊断源码契约适配
状态：源码契约修复已验证；整体 UI 验收未完成。
代码：[55351e1](https://github.com/qianshou330-cyber/pubo-ios/commit/55351e1922a1141ddc3eecd7e720f853bc4b232f)
问题：C60 核心检查中两条源码断言失败，仍要求旧的 `isHittable == true` 和 guard/return 字面形式。
原因：诊断代码缓存了同一次原生可点击读取，旧静态契约未识别等价结构；这不是已证实的页面功能故障。
修改：明确保留 `button.isHittable == true`；契约检查完整有限/正尺寸/相交条件先于唯一可点击读取，非法几何保留 nil 且不能通过。保留 20 秒存在等待、8 秒就绪、实际点击、选中断言及禁止坐标兜底。
文件：
- `UITests/AppNavigationUITestSupport.swift`
- `scripts/test_tab_geometry_readiness.py`

验证：
- 本地 `python3 -m unittest discover -s scripts -p 'test_*.py' -v`：136/136 通过。
- 本地 `node --test scripts/isolated/test-room-message-proof.mjs`：2/2 通过；`git diff --check` 通过。
- 本地 Swift 核心、Swift 几何与刷新诊断无法运行（Linux 无 Swift）；Darwin 预检无法运行（非 macOS）。不算通过。
- [C61 CI](https://github.com/qianshou330-cyber/pubo-ios/actions/runs/44117699042)：核心检查成功，解决 C60 前置阻塞。小屏页面状态 4/4、大屏旧回归 5/5，均有成功退出证据。大小屏聊天操作作业成功，但本记录未复核小屏方法计数。
- 此日志建立时仍有 UI 作业运行或排队，不能称全量通过。

未解决：
- 小屏旧回归、大屏视频、大屏页面状态在 XCTest Accessibility 初始化超时，未进入功能场景。
- OCR 仍拒绝 3 个固定合成正样本；大屏导航失败需读原始日志。
- 候选包两种 Release 编译成功，但产物服务 CreateArtifact 5 次超时，当前没有可下载候选包。整轮结束后再考虑只重跑该打包作业。
- 真机安装/签名/覆盖、相机、APNs、最低 iOS17 与实际滚动体验未验收。就绪诊断成功样本不能证明旧间歇故障根因。

## 2026-11-17 / C60 / 增加导航就绪采样诊断
状态：诊断，不是根因修复；前置契约失败后由 C61 修正。
代码：[2484475](https://github.com/qianshou330-cyber/pubo-ios/commit/2484475b348bece7043a6cc70272a9697d4b7829)
问题：多项测试在进入消息栏时就绪等待失败，旧日志无法区分窗口/按钮几何与可点击状态。
修改：复用原来的窗口、按钮 frame 和条件可点击读取，最多缓存 16 条采样，等待结束后才输出；不新增 AX/截图查询、不延长门槛或重试。
文件：
- `UITests/AppNavigationUITestSupport.swift`
- `scripts/test_tab_readiness_diagnostics.py`

验证：
- 本地新增源码不变量测试 6/6 通过，包含 32 种布尔组合等价检查；当时未运行完整 Python 集合，这是验证覆盖缺口。
- [C60 CI](https://github.com/qianshou330-cyber/pubo-ios/actions/runs/44114104423)：核心检查失败于 2 条旧源码契约；下游 UI/打包跳过。不得将跳过视为通过。
- 后续 C61 跑完整本地集合并修复契约；实际 CI 已输出采样。

未解决：原始间歇就绪、截图、初始化和结束清理超时；诊断采样不等于修复。保留原 1800 秒测试预算及严格成功退出要求。

## 2026-11-17 18:03 UTC / C61 screenshot evidence inventory
Status: evidence inventory only; QA INCOMPLETE, not visual acceptance.
Code: `55351e1922a1141ddc3eecd7e720f853bc4b232f`; [run 44117699042](https://github.com/qianshou330-cyber/pubo-ios/actions/runs/44117699042).
- Verified 8 baseline pairs (private/room × small/large × light/dark), 16 original PNG files. Private captures are in layout artifacts 14352065341 / 14351519255; room captures in actions artifacts 14349472670 / 14349480581; H5 reference artifact 14343668173.
- All 16 PNG files decode and have SHA-256 manifests in the prepared evidence archive. Small pairs are 750×1334 on both sides. Large iOS originals are 1320×2868, H5 880×1912 (different raster scale); do not compare unnormalized raw pixels.
- H5 is an actual public bundle snapshot with synthetic ChatParity fixtures and blocked production APIs, not a live production-account recording. iOS captures are Simulator screenshots, not physical-device verification.
- Inspected private-small-light pair visibly differs in header, spacing and reaction rendering. Pair availability and passing scenario assertions do not establish 1:1 parity. Full visual review and outstanding failed suites remain open.
- Changes: documentation only (`docs/FIX_LOG.md`, `docs/AGENT_HANDOFF.md`); no code, gate, retry or timeout changes and no new CI run.
