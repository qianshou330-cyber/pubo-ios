# 修复日志

## 2026-11-18 19:44 UTC / C69 final evidence (not accepted)
Code: `13b2c02638a59671cc9bcac56bc69b20fa168abf`; [run 44351644804](https://github.com/qianshou330-cyber/pubo-ios/actions/runs/44351644804), completed **failure**. Branch head rechecked; no in-progress run. This update changes documentation only, not app behavior, diagnostics or gates.

- Passed jobs: checks (180 Swift tests including both new confirmed-privacy-draft regressions; 159 Python tests), H5 reference, both layout sizes, small video, large actions, large states. Candidate packaging succeeded only as **QA-INCOMPLETE**; formal package skipped.
- OCR: known three positive confidence failures remain; original thresholds and negative protections unchanged.
- Small navigation (job 134974652479): cancelled overall after 13 tests / 1 assertion failure and later simulator shutdown timeout. Failure is initial syntheticpeer row absence at FourTabNavigationUITests:372, BEFORE any account switch. Original recording `616C185A-ADD4-42DC-B181-FBF8333BE01B.mp4` (artifact 14454964979) shows message-list spinner. Do not label account-isolation failure or repaired loading.
- Large navigation (134974652304): 12 individual test pass records, final test started but no final result; runner exceeded 2700 seconds. Incomplete suite, not 13/13.
- Small legacy (134974652321) and small composer (134974652372): UI runner AX initialization timeout, not product assertion failures.
- Large legacy (134974652344): 5 tests / 1 failure at initial 我的 tab readiness, BEFORE privacy edit/save. The C69 privacy helper is unit-verified, but the end-to-end privacy UI save flow was NOT verified by this run.
- Large video (134974652341): 4 tests / 1 failure at initial 世界圈 readiness in broken-thumbnail case, before thumbnail decoding assertion.
- Large composer (134974652351): all four individual test pass records, but runner exceeded the 30-minute budget and result bundle metadata/export failed. Job remains failed/incomplete, not fully accepted.
- Small actions (134974652529): 5 tests / 1 failure at initial 消息 readiness in group reaction case; group permission behavior was not reached in that failed case.
- Small states (134974652599): 4 tests / 1 failure; initial-failure-retry case failed at ChatComposerParityUITests:23 querying chat.input after opening private chat. Retry was NOT attempted. Other three tests passed. Artifact 14460397554 contains original recording `59FCAD98-E800-4F9C-B16B-AEC7F4606F8B.mp4`, query attachment `799AFD39-8450-4860-B485-C1FBE2E87927.txt`, and lifecycle logs.
- Small states PID 18944: timeline request 18:43:51.492; transport fail-once/exit 18:43:56.561/56.563; catch 18:45:36.209; load-exit 18:45:36.222 with loading=false/errorPresent=true. Approximately 99.65 seconds between transport exit and catch. Original video inspected near its end still displays 正在加载消息. Startup probe also records 102.31-second and 30.99-second pulse gaps. These establish delayed continuation/visible progress, NOT a proven CPU/main-thread deadlock, transport hang or failed retry. Test/host suspension, scheduler/AX overhead, diagnostics overhead and delayed rendering remain possible; timestamps alone cannot distinguish them.

Changes/files: only this log and AGENT_HANDOFF. No rerun, code change, lowered gate, new branch, PR, release or accepted IPA. Next: investigate the existing synthetic loading/lifecycle path and correlate original video/logs before selecting a reproducible fix. Existing ChatList task already invalidates stale epochs; do not reintroduce or claim that old fix as new. Preserve all failure and incomplete-run evidence.


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

## 2026-11-17 23:38 UTC / C63 小屏通过与恢复专项仍失败
状态：布局/标识目标局部验证，恢复流程未验收；大屏actions仍活动，不推代码/重跑。
代码171b11f；[run44182546174](https://github.com/qianshou330-cyber/pubo-ios/actions/runs/44182546174)。
- 原始日志确认small layout5/5、small actions5/5成功。大小屏layout均通过，包括双主题原chat.text查找、菜单往返、反应/搜索及几何。small layout artifact14379825039下载并提取原图，浅色图已查看；未将截图等同于全部流程通过。
- small states4项2失败：初次失败重试恢复在line224获取chat.text.private0001快照超时；群发送者名line237的hittability查询报无有效激活点。初始加载/空状态、链接预览重试方法通过。
- 重要反证：恢复测试原录像（artifact14376789899）总长197.14s，末尾约192s画面仍为“正在加载消息…”。日志约74s点重试、76s重试按钮消失，随后正文查询始终未成功。因此“按钮消失”不证明加载完成，不能断言只是ID或AX问题；可能仍有加载生命周期/异步fixture或同步阻塞，根因未定。导出的正文debug附件只有查询链，不含可证明正文已出现的树。不能把C63标识局部恢复称整个重试恢复已修复。
- large states在AX loaded初始化超时，未进入恢复场景。large composer4/4方法失败（快照/终止等），随后原1800s预算/清理超时；small composer4项1失败于启动后的查询，其他3方法通过。small legacy5项1失败于我的栏就绪，编辑冲突/响应丢失草稿用例通过。各失败不互相替代。
行动：只读原日志、截图与恢复录像；不弱化断言、不延长预算、不盲目重跑。原菜单/正文查找和加载完成条件保留。下一步待最后作业结束后，围绕重试请求生命周期与fixture响应增加有界诊断，区分等待网络、同步状态、取消/epoch失效和加载标记，不以隐藏加载指示替代真正完成。正式包仍未验收，不重复交付旧包。

## 2026-11-17 22:39 UTC / C63 大屏正文标识与布局证据
状态：大屏目标场景已验证，恢复用例/小屏仍待；整体未验收。代码171b11fa01a6d10fb93a2bf838d6d62c6951f115；[run44182546174](https://github.com/qianshou330-cyber/pubo-ios/actions/runs/44182546174)。
- 大屏layout作业成功5/5，原始日志确认testPrivateSearchDateAndReactionsBothThemes于22:09:21通过。该场景直接读取原chat.text标识，执行菜单实际打开/关闭、反应、搜索和严格几何断言。因此原正文标识已在此大屏明暗场景恢复可查；不能据此替代单独的失败恢复场景。
- 下载artifact14376040293并核对4份真实几何附件：双方菜单均44×44pt，正文约139/140×15.33pt，元数据约13.33pt；与C62布局尺寸一致。真实大屏明暗截图已提取，不使用C62图代替。它们仍是模拟器/合成fixture，不是完整验收或真机。
- 核心Swift178/178、Python140/140及H5成功；候选包作业成功且artifact14374964353存在，仍标QA-INCOMPLETE；本轮未下载验证IPA，不称已交付。
- 大屏导航13项1失败，原始失败是账号切换方法FourTabNavigationUITests.swift:17获取匹配快照超时；不是13项全失败。小屏视频4项1失败于世界圈就绪；大屏视频和大屏旧回归在AX初始化超时，未进入场景。OCR仍为原三个正样本失败。
- 最新已查状态仍有5项运行、4项排队；大小屏states恢复、small layout与菜单actions尚无最终结果，明确列为待验证而非失败或通过。
行动：仅读取日志/附件及更新本文和交接，不重跑、不推送新代码、不取消当前作业；文档提交skip ci。下一步等待小屏、恢复场景和剩余组完成，确认前不称C63全量修复。

## 2026-11-17 21:42 UTC / C63 / 恢复私聊正文可访问性标识
状态：最小修复候选，本地验证通过；真实 AX 恢复与新版视觉结果待本提交 CI，不称验收完成。
基线：813079a87ec0af095ee8e17ac5007729ac656843（产品 C62 58edda3）。提交前已核实 C62 全部结束，仓库无运行/排队工作。
问题：C62 大屏恢复测试在 ChatComposerParityUITests.swift:224 等待原 chat.text.private0001 失败；新增祖先 chat.bubble 标识在实际附件返回正文尺寸，与既有祖先ID覆盖UIKit内层ID机制一致。属于本次改动引入的标识回归线索，不笼统归因环境。
修改：移除 ChatView 的外层 chat.bubble 标识，保留原 ChatMessageContent 的 chat.text；几何测试直接测已有正文元素，附件用 text= 明确测量范围；新增契约防止祖先标识再次遮蔽。没有更改菜单布局、44pt点击区域、动作权限、元数据几何条件、真实菜单往返、旧恢复测试或任何等待/作业预算。
涉及文件：App/Features/ChatView.swift；UITests/ChatAlignmentUITests.swift；scripts/test_chat_private_metadata_layout.py；docs/FIX_LOG.md；docs/AGENT_HANDOFF.md。
测试：完整 Python 140/140、Node 收据2/2、git diff --check 通过。Linux无Swift/Xcode，本地未编译Swift或执行模拟器；需等待正常触发的完整CI验证，代码提交不使用skip ci。
C62最终补充：大屏navigation成功13/13（原始日志及作业结束成功已核实），但整轮仍失败，formal package跳过。其他失败与局部成功保留前述记录，不用单组成功覆盖历史失败。
下一步：本提交 CI 重点检查恢复状态用例重新找到 chat.text、私聊大小屏明暗几何与菜单、既有其他回归，并重新取得同版本截图。OCR与模拟器/AX慢查询等问题不在本修复范围。

## 2026-11-17 21:00 UTC / C62 小屏确认与正文标识回归线索
状态：仍未整体验收，最后核查大屏导航/大屏composer仍运行；不启动重叠作业。
代码58edda3；[run 44156868718](https://github.com/qianshou330-cyber/pubo-ios/actions/runs/44156868718)。
- 小屏layout已成功5/5，含目标私聊双主题真实菜单往返/几何；小屏actions也成功5/5。同版本小屏artifact14368805326已下载，附件显示菜单44×44pt、时间行13.5pt。结合上一记录，大/小屏私聊目标场景均通过，但大屏layout全组仍失败。
- 大屏states恢复用例在ChatComposerParityUITests.swift:224等待chat.text.private0001失败。C62新增外层chat.bubble标识，而实际bubble附件返回正文尺寸；结合仓库既有祖先ID替换UIKit内层ID的记录，提示C62引入正文AX标识遮蔽回归。不能把此失败笼统归为环境。
- 已在本地准备C63最小候选：移除ChatView外层chat.bubble标识；几何测试改用既有chat.text元素并明确附件text=，保留所有尺寸、可点击、菜单往返与恢复断言。新增契约阻止遮蔽。完整Python140/140、Node2/2、diff检查通过；未Swift编译/运行，未推送，待当前CI结束后再核实并发。不是已验证修复。
- 旧回归大小屏各5项2失败；小屏在我的栏就绪/消息菜单稳定等待，大屏在消息操作查询快照/主页导航断言。需分别分析，不等同于当前私聊视觉目标失败。
- 小屏视频未进入场景：AX loaded通知初始化超时。大屏视频4项3失败在世界圈就绪，缺缩略图解码场景通过。
- 小屏composer前三个方法通过，但最后方法未完整结束，整体超过原1800秒预算，终止后wait(30)再次超时；不能把末尾30秒误写成整个测试预算。结果包读取失败。
下一步：等待最后两项结束；如无并发，在授权分支正常推送C63后验证旧恢复场景及新几何。C62候选包成功仍不构成完整可交付验收版，不重复交付C61。

## 2026-11-17 20:35 UTC / C62 首轮视觉与运行时证据
状态：大屏私聊目标场景通过，整体未验收，CI 仍有活动/排队工作。代码 58edda3b31eaad94d42c66c4d7b8e93bf11032db；[run 44156868718](https://github.com/qianshou330-cyber/pubo-ios/actions/runs/44156868718)。本次只读检查与文档记录，不推送新代码、不重跑作业。
- checks、H5、candidate-package、大屏聊天 actions 作业成功；候选包仍标 QA-INCOMPLETE，构建成功不代表整体验收。
- 大屏 layout 作业整体失败（5 项中的 2 项失败），但 testPrivateSearchDateAndReactionsBothThemes 在 20:21:58 明确通过，包含新增的明暗主题双方菜单尺寸/真实点击往返与元数据几何、原反应和搜索。不能把这个方法通过写成 layout 全组通过。
- 已下载同 SHA 大屏 layout artifact 14368080161 和 H5 artifact 14361173014。真实元数据附件：双方菜单均 44×44pt，时间行约13.33pt；截图确认菜单已在气泡侧、时间行不再由44pt按钮撑高。浅色原图已人工查看；明暗原图已按原比例制作对照，仍是模拟器+合成 fixture、不是生产账号/真机或1:1一致。
- AX 的 bubble 标识当前返回正文可访问区域（大屏约140×15.33pt），不是含所有内边距的完整背景矩形。因此不重叠断言证明菜单未覆盖正文与元数据，不应夸大成完整气泡边界像素验证；截图补充目视证据。长文本/附件/大字体私聊仍待验证。
- 大屏 layout 的两个失败分别在进入消息栏的就绪等待、进入群聊的输入框等待（ChatAlignmentUITests.swift:76），不是新增私聊断言。首次就绪样本几何合法且 hittable=true，但窗口查询1.210s、frame查询4.191s、hittable查询1.658s，加开始延迟1.068s，采样结束8.127s，已超过8s预算；这是慢AX查询耗尽预算的直接证据，仍未锁定造成查询变慢的底层原因。不增加预算、不省略真实可点击检查。
- 小屏 navigation 超过原2700秒预算且结果包读取失败；小屏 states 4项中1项失败于消息栏就绪；OCR仍是同三个正样本拒绝。其他失败尚未全部查完，不混称全是环境故障。
下一步：待剩余作业完成，优先核实小屏私聊目标场景和截图；继续保留整体失败及门槛。纯文档 skip ci 用于记录，不取消当前运行。

## 2026-11-17 19:15 UTC / C62 / 私聊元数据行与菜单触区分离
状态：修复候选，本地源码契约通过；Swift 编译、真实帧与更新截图待 CI，不能称视觉验收完成。
基线：581709b8192721c86fd8124bd27a616fc5994276（产品代码 C61 55351e1）。
问题证据：同一 C61 run 44117699042 的小屏浅色私聊对照，iOS 气泡与反应之间的时间行明显比 H5 高。代码确认 ChatView 将 44pt 菜单放入元数据 HStack，撑高整行；RoomChatView 已将菜单移到气泡旁。
修改：私聊采用与群聊一致的可见气泡侧菜单，自己消息菜单在气泡左、他人消息在右；菜单保持真实 44×44pt、矩形触区、原读屏标签/ID、共享 messageMenu/messageActions 与会话权限防护。时间、已读、已编辑信息及反应逻辑保留。没有通过透明 overlay、负 padding 或缩小点击区域减少空隙。
文件：App/Features/ChatView.swift；UITests/ChatAlignmentUITests.swift；scripts/test_chat_private_metadata_layout.py；docs/FIX_LOG.md；docs/AGENT_HANDOFF.md。
测试：
- 本地完整 Python 139/139 通过（新增 3 条契约）；Node 收据测试 2/2；git diff --check 通过。
- 既有双主题私聊场景新增双方消息的实际菜单/气泡/元数据 frame 断言：44pt、可点击、互不覆盖、普通字体元数据低于44pt，间距不超过7pt；新增双方侧边菜单真实点击→原消息操作 sheet→关闭的往返检查；保留原反应点击、搜索断言及原截图。新增检查使用8秒有界等待相同严格几何，避免 AX 元素先出现而入场动画未完成；未延长现有等待或作业预算。只读复核未发现明显语法/权限回归，强调横向空间和运行时验证风险。
- Linux 无 Swift/Xcode，未运行 Swift 编译或模拟器；新增运行时断言未运行，不算通过。大字体/长文本/附件布局仍需既有完整 UI 验证，新边栏会占用横向空间，不宣称无折行差异。
范围与下一步：仅处理可定位的元数据空隙，系统导航、emoji 图形、输入区、OCR 与其他 C61 故障仍未修复。等待本提交的真实 CI 及同版本 H5/iOS 截图后判断效果，不用旧 C61 图片冒充 C62。提交前重新确认无活动作业；代码提交正常触发完整 CI，不使用 skip ci。

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


## 2026-11-18 00:18 UTC — C63 final status / C64 recovery diagnostics (not a repair)
- Refreshed branch at 080c5cca40b638aa65aa87db4b16609f04f51177 and run [44182546174](https://github.com/qianshou330-cyber/pubo-ios/actions/runs/44182546174). All C63 jobs finished; overall failure; formal package skipped. Large actions ended failure, but its raw job-log fetch twice returned BlobNotFound and no matching actions artifact was listed, so exact failure is not established. No active branch run before preparing C64.
- C63 small recovery video still shows loading after retry (prior evidence). Source review narrows interpretation: ChatTimelineStatus displays spinner when not loaded OR loading. Thus loading=false/loaded=false/error=nil can also display indefinitely. load clears error, then an epoch/cancellation early return can leave that state. This is a reachable path, NOT a proven explanation of C63. Retry disappearing proves neither request completion nor recovery.
- Fixture review: this scenario uses a five-second delay plus first-request failure, not the response gate. Second request should return fixture messages; state endpoint is synchronous fixture data. Need evidence to distinguish transport suspension, cancelled/stale result, lifecycle disappearance, and UI/AX stall.
- C64 changes: synthetic-only DEBUG stage logging in App/Features/ChatView.swift and App/Infrastructure/FixtureTransport.swift; stage-only unified-log export in scripts/simulator-tests.py for the existing states shard; source guards in scripts/test_chat_load_trace.py. Log only fresh diagnostic attempt IDs, stage, booleans, and counts; never message contents, account IDs, credentials, or error text. Existing artifact build/*.json includes logs. Missing capture is explicitly incomplete, never acceptance.
- All original epoch/cancellation/active guards, genuine retry tap, message assertion, 15-second waits, fixture five-second delay, OCR gates and workflow trigger/concurrency remain unchanged. No speculative product-state change. Normal code CI is required; do not use skip ci.
- Local passed: Python 143/143, Node receipt tests 2/2, git diff --check. One first draft broke a literal fixture-delay source contract by inserting a log inside its line; corrected by keeping the original line exactly and observing afterward; final suite passes. Swift geometry command was attempted but blocked by missing swiftc; Xcode/Swift compile and real simulator results are NOT locally verified.
- Next: inspect same-run chatload-diagnostics and capture status with retry recording. timeline-return/current=false or cancelled=true identifies discarded results; transport-exit without timeline-return points above transport; load-exit/loaded=false/loading=false confirms idle spinner. No terminal stage plus UI freeze requires lifecycle/runtime evidence, not longer timeouts. C64 is diagnostics only, OCR and recovery remain unresolved.


### C64 follow-up — 2026-11-18 00:39 UTC (partial, running)
- Code SHA 236cc491176045e72f992e3a64f39a7d6047f013; [run 44206712654](https://github.com/qianshou330-cyber/pubo-ios/actions/runs/44206712654) is still running. Checks, candidate-package and H5 reference succeeded; small states, large layout/composer and both video shards are running; remaining shards/OCR queued at this snapshot.
- Raw checks log confirms Swift 178/178, Python 143/143 and Node receipt 2/2. Candidate raw log confirms two BUILD SUCCEEDED entries (simulator/device packaging). Artifact 14383994072 exists and remains QA-INCOMPLETE; not downloaded or installation-verified, not an accepted release.
- No states artifact has uploaded yet. Recovery-stage logging and retry outcome are therefore still UNVERIFIED; a successful package is not evidence that recovery works. No code changes, retries, cancellations or new diagnostic runs started in this check.
- This follow-up touches documentation only with skip ci, preserving active C64. Wait for states evidence before choosing a product fix; retain all gates.


### C64 recovery evidence — 2026-11-18 01:43 UTC (CI still active)
- [Run 44206712654](https://github.com/qianshou330-cyber/pubo-ios/actions/runs/44206712654), code 236cc491176045e72f992e3a64f39a7d6047f013. Branch refreshed at 8673dad334698b5cd779b7aef95bb461ee3a31de. Large actions/legacy/navigation, small composer/navigation remain active; no code push or rerun during this check.
- Small states job 134476222863 failed before scenarios: XCTest runner timed out waiting for AX loaded notification. Artifact 14385955493 downloaded: chatload-capture-0.json INCOMPLETE, exitCode 0, diagnostic event array empty. This is NOT an executed recovery failure or pass.
- Large states job 134476223058 ran 4 tests / 2 failures. Retry scenario failed at ChatComposerParityUITests.swift:23 inside open(), waiting for chat.input after tapping conversation.user:syntheticpeer. The app-idle notification was not received; subsequent snapshot query timed out. Retry was never tapped. Loading/empty and link-preview retry cases passed; sender-name case failed at initial messages-tab readiness, before preference validation.
- Artifact 14387495934 downloaded; chatload-capture-0.json also INCOMPLETE with zero stage events. Original retry-case recording EB0B56D3-844D-468C-9CF4-67146170B988.mp4 is 208.368 seconds. Inspected final frame about 203 seconds: still on message conversation list, not the private chat/retry screen. This supports an earlier navigation/automation stall; it does not establish the C63 persistent-spinner cause or prove diagnostic logging works.
- Other verified raw counts: large layout 5/5, small actions 5/5. Small layout failed at AX initialization before scenarios. Small video is cancelled (raw log currently BlobNotFound; cause not established). OCR, large video/composer and small legacy failed; do not equate this partial run with acceptance.
- No speculative state repair is justified by these artifacts. Preserve C64 traces; next investigate conversation navigation/idle stall or rerun the isolated failed states job only after all current jobs finish and concurrency is rechecked. Do not increase timeouts, bypass real taps, hide spinner, or claim empty diagnostic output means success. Docs-only skip-ci checkpoint preserves active work.


### C64 isolated states retry — 2026-11-18 02:49 UTC
- Refreshed branch at 2fedd9389b2121a81e5d07de19ef0ac6689d0273 and confirmed all C64 attempt-1 jobs completed, overall failure; no other active test-branch run. Large navigation eventually succeeded; small navigation/video cancelled; remaining final failures are preserved, formal package skipped.
- Authorized single-job retry requested ONLY for small states old job 134476222863, which previously never passed AX initialization. Tool confirmed success. Same C64 code 236cc491176045e72f992e3a64f39a7d6047f013, [run 44206712654 attempt 2](https://github.com/qianshou330-cyber/pubo-ios/actions/runs/44206712654/attempts/2), active new small-states job 134539167538. Preparing fixed build tools at verification; no new test result yet.
- No all-failed rerun, no product code change, no trigger/timeout/gate changes. Large states was not separately retried: its attempt-2 listing is a carried-forward completed failure with original 00:41–01:06 timestamps (new listing ID 134539228764), not a fresh execution. Wait for small-states outcome before deciding further retry.
- This documentation-only skip-ci commit records the action without cancelling it. Inspect actual retry tap, stage captures and recording; keep capture INCOMPLETE distinct from success. C64 remains diagnostic and QA-incomplete.


### C64 small states recovery verified once; large retry — 2026-11-18 03:30 UTC
- Same code 236cc491176045e72f992e3a64f39a7d6047f013; attempt 2 small-states job 134539167538 succeeded. Raw log verifies 4/4: explicit failure/retry recovery, loading/empty, link-preview retry, sender-name preference. Genuine chat.retry tap at 03:02:37 and room.retry at 03:04:23; existing assertions/timeouts unchanged.
- Downloaded artifact 14393603421 (do not confuse with failed attempt-1 artifact 14385955493). chatload capture CAPTURED, exit 0, 18 events. Private first request entered 03:02:30.902, failed once after delay at 03:02:36.101, exited with errorPresent=true/loading=false. Retry entered 03:02:38.073; second transport returned at 03:02:43.144; timeline-return 03:02:43.741; published 03:02:43.769 with count=2/loaded=true/current=true/cancelled=false; load-exit loading=false/errorPresent=false. No state batches were needed in this fixture path. This proves one successful recovery lifecycle, not the cause of earlier stalls.
- Inspected original recovered private PNG 4772FDE9-73F3-4A3F-B836-AE4F9EA5408D.png and room PNG FAAA9F3E-CF06-4097-9E56-7639E306C609.png: actual message bodies and composer visible. Successful retry artifact contains screenshots, not a recorded video; do not claim a recovery video was inspected. Room recovery is proven by original UI test/screenshot, not private-only stage traces.
- No product repair occurred between failure and this pass; diagnostic code unchanged. C63 persistent spinner root cause is still unconfirmed, and one rerun does not prove stability or overall acceptance.
- Confirmed all branch runs completed before proceeding. Requested ONLY large states carried-forward failed job 134539228764. Tool succeeded; attempt 3 now has active job 134555169924, same code/run [44206712654](https://github.com/qianshou330-cyber/pubo-ios/actions/runs/44206712654/attempts/3). No full-failed retry or other code/threshold change. Await result; all unrelated failures remain visible.
- Documentation-only skip-ci checkpoint. C64 remains QA-incomplete, no release/PR/main change.


### C64 large states retry failed before recovery — 2026-11-18 04:05 UTC
- Attempt 3 job 134555169924 completed failure: 4 methods, 3 passed. Loading/empty, link-preview retry and sender-name preference passed. Explicit retry-recovery failed at initial messages-tab readiness (ChatComposerParityUITests.swift:14), before tab tap, conversation navigation or retry.
- Original readiness sample: one evaluation; window query took 7.254364 seconds, window 440x956, returned tab frame (0,0,0,0), framePositive=false/intersects=false; hittability correctly not queried. Existing 8-second readiness budget expired. This is a real failed readiness gate; do not substitute visible pixels for usable accessibility geometry or increase the budget.
- Downloaded artifact 14395159445. Stage capture INCOMPLETE, zero events, collection exit 0. Original failure recording 5CDB145A-CD8E-42CB-AB6F-4E08E19436F6.mp4 inspected near its end: message list/tab bar visible, no private-chat/retry screen. Query debug attachment contains only the query chain, not a full AX hierarchy. Visual presence with returned zero frame does not prove hittability or identify a product root cause.
- Both isolated states retries have now ended; no active job in current run. Small states retains its single 4/4 pass and complete 18-event lifecycle from attempt 2; large recovery remains untested beyond entry readiness. No new product fix or another blind rerun was made. Earlier failed attempts remain preserved.
- Next investigation should target startup accessibility readiness/snapshot latency before retry logic: compare first-launch and subsequent-launch query timings, retain actual window/frame/hit requirements, collect evidence without changing test order or filtering the failing case. C63 persistent-spinner hypothesis remains unconfirmed. Overall C64 still fails; not release acceptance.


### Read-only startup accessibility audit — 2026-11-18 04:53 UTC
- Refreshed branch at 6fa205c5fce201059c569753fbf286081fc7b6d3; latest runs are completed. Compared original C64 large attempt-3 and small attempt-2 logs, current AppNavigationUITestSupport/BottomTabBar sources, and original boot/environment receipts. No code patch or new CI execution was justified or started.
- Large attempt-3 first launch: window-frame query 7.254364 s; following button-frame query 0.004612 s returned zero rect; native hittability deliberately not queried because geometry invalid. Predicate begins about 1.003 s into unchanged 8 s wait, so one remote query consumes the remaining budget. This is query latency, not evidence that the 56pt touch target is too small.
- Same large job's SIX later launches: all single-sample readiness passes, window queries 0.0178–0.0232 s, button frames consistently (0,866,110,56), native hittable=true followed by actual tap and selected assertion. Small retry's EIGHT samples also passed, window queries 0.0186–0.0613 s, frames (0,611,94,56), true hittability. This establishes observed first-launch concentration in this job, NOT a universal first-launch defect or simulator-only cause.
- Both task-owned simulator boot receipts report READY on first boot attempt. Large environment: iPhone 17 Pro Max, iOS-26-1 runtime, x86_64, Xcode 26.0.1 (17A400). Successful simctl bootstatus did not establish app accessibility readiness. Startup AX errors in other C64 shards reinforce the investigation priority but do not prove causality.
- Source review: tabs are real Button controls, minHeight44 plus vertical padding, plain style and explicit rectangular contentShape; badges disable hit testing. Existing geometry/intersection guard precedes isHittable; selected assertion follows actual tap. No demonstrated layout or hit-target defect supports changing these controls. Conversation suppression begins only in destination onAppear; this failed sample occurred before conversation navigation.
- Keep threshold, order and controls unchanged. Do NOT cache a previous valid frame, trust screenshot geometry instead of AX, skip the initial tab tap, add a warm-up launch, reorder cases, or extend timeout to turn the observation into a pass. Such changes would obscure the failed cold entry.
- Next evidence needed before product repair: synchronized app-side main-thread/layout lifecycle timing versus native AX query timing during a failing first launch, plus runner/system responsiveness. Any added observation must stay synthetic-only, avoid extra synchronous AX calls within the readiness budget, and preserve original failed outcome. Existing evidence cannot distinguish stale AX snapshot, snapshot service stall, or main-thread responsiveness. No claim of root cause or fix; C64 remains incomplete.


## C65 — 2026-11-18 06:16 UTC — bounded startup/main-layout diagnostics, NOT a product fix
- Starting from a2710b438e6f040c632470be10c77bc78a596bd4, inspected AppSession construction, PUBOApp task/scene lifecycle, BottomTabBarInset and native UI readiness helper. Construction performs synchronous fixture store/cache setup; later startup uses awaited fixture install. Existing logs cannot attribute the cold-entry 7.25s AX window query to either work, so no production behavior change is justified.
- Changes: new App/Infrastructure/StartupAccessibilityDiagnostics.swift; DEBUG hooks in App/Infrastructure/AppSession.swift and App/PUBOApp.swift; background-only modifier in App/Components/BottomTabBar.swift; states-only export in scripts/simulator-tests.py; source contracts in scripts/test_startup_accessibility_diagnostics.py.
- Enabled only with DEBUG, --ui-testing, --chat-load-fail-once and no --isolated-backend. Record session init/start return, scene lifecycle, global BAR-container geometry (not button AX geometry), PID/monotonic uptime, and MainActor scheduling intervals. At most one 60-tick/1-second sampling task per process, independent of session.start(), no UI state changes, cancellation exits immediately. Total cap128, layout cap32, reserved terminal capacity. No account/message/credential data. The transparent background cannot receive touches or become an AX element.
- Collector uses existing task-owned simulator and subsystem-filtered 1-hour retention window, covering original 30-minute UI budget plus export. Exit status and missing marker remain INCOMPLETE; neither layout nor scheduling samples satisfy acceptance. MainActor gaps can include host scheduling/suspension, and missing logs can mean cancellation/process termination or collection failure, not necessarily main-thread blocking. Instrumentation can mildly perturb scheduling; do not claim zero-impact reproduction.
- Original UI test source, 20-second existence / 8-second readiness / actual click and selection assertion, 15-second recovery, fixture responses, OCR and workflow concurrency untouched. No warm-up launch, reordered cases, fake frame, cached geometry or threshold changes. Normal full CI required; code does not use skip ci.
- Local passed: Python147/147, Node2/2, Python compilation, diff check. Swift/Xcode unavailable here, actual native compilation and simulator validation pending. Code reviewed for MainActor ownership, bounded/cancellable sampling and passive geometry; do not treat source contracts as runtime proof.
- Next: align failed AX query UTC intervals with same-process pulse/scene/layout records. Normal pulses plus valid app layout during a failed query narrow the fault toward accessibility snapshot/query handling; long pulse gaps require further host/app evidence. C63 retry root cause and overall acceptance remain unresolved.


### C65 partial CI checkpoint — 2026-11-18 06:34 UTC
- Code fa7faa575afce408fffc444c613b79a7abf9bc91, [run 44250136745](https://github.com/qianshou330-cyber/pubo-ios/actions/runs/44250136745) active. Small states running, large states queued; no states artifacts yet. Startup/main-layout timing evidence and app compilation cannot yet be asserted from completed core checks.
- Read raw completed logs: Swift core178/178, Python147/147, Node2/2 pass; H5 job success. OCR policyRegression FAIL on the same three previously readable controls (DejaVuSans-3x-10pt-1, 10pt-99plus, 12pt-5). Gate and corpus remain unchanged.
- Candidate build and other simulator jobs running/queued. No code push, rerun, cancellation or new experiment during active work. No stage/geometry/root-cause conclusion without actual states artifacts. Documentation-only skip-ci checkpoint; overall acceptance remains incomplete.


### C65 small states timing evidence — 2026-11-18 07:07 UTC (large still running)
- Small states job134619784052 raw result 4/4 pass; artifact14405017469 downloaded. Both startup and chatload captures contain events. All eight tab samples satisfy real finite geometry/native hittability; real taps/selection and recovery assertions remain unchanged. Large states job134619784149 still running; no large timing conclusion yet. Other jobs also active; no code push/retry.
- First private process PID23998: init about0.069s by monotonic timestamps; root start-to-return about0.270s; bar appeared06:39:14 with global container(0,611,375,56), well before native tab query06:39:28 (button94x56, true hittability). Thus this successful sample does not reproduce C64's initial zero AX frame and does not identify a startup-init defect.
- Private recovery: fail-once observed, actual retry-enter06:40:41.549; timeline returned06:40:47.245, published2 messages and exited loading=false/loaded=true/errorPresent=false at06:40:47.248, about5.70s after retry. The UI test also verifies room recovery. Successful output includes original failed/recovered PNGs, not a video.
- New observation: PID23998 main-scheduling intervals include27.372s ending06:40:00.786,32.954s ending06:40:38.662,31.256s ending06:41:18.493. These overlap navigation idle/snapshot waits. The later room process PID30241 has max observed gap4.056s. Both contain sceneActive, no observed sceneInactive/background event; absence is not proof of uninterrupted execution.
- Interpretation LIMIT: these are times between executions of a sleeping MainActor probe, NOT measured CPU blocking durations. Task.sleep resumption, executor/host load, test-induced process/snapshot suspension, logging overhead, cancellation, and the probe's own scheduling effects can contribute. No off-main control sample, stack trace or scheduler trace exists to separate them. Do not claim main-thread blockage or purely AX-service delay. Correlation narrows the next investigation only.
- Probe is bounded by60 ticks, NOT a hard60s elapsed deadline: delays can stretch elapsed lifetime. This run has51 and44 pulse records respectively, no pulseEnd, consistent with processes being terminated by UI tests but not proof of the reason. No cap reached(59/52 total records). Earlier shorthand “60-second sampling” must be read as nominal cadence, not wall-clock guarantee. Consider a monotonic deadline in a future diagnostic-only revision, without changing acceptance.
- Raw XCTest waits can themselves overrun nominal budgets during synchronous query calls; tests passed under original APIs, not a new hard wall-clock responsiveness assertion. Overall performance/acceptance is still unresolved. Preserve original failures and all current gates; do not infer a repair from the passing small run.


### C65 both-size states verified — 2026-11-18 07:42 UTC (not whole acceptance)
- Large states job134619784149 raw log confirms4/4, matching small4/4 on the SAME code fa7faa575afce408fffc444c613b79a7abf9bc91. Downloaded artifact14407360953, startup/chatload captures both CAPTURED. This is successful execution of existing recovery/loading/link-preview/sender-preference cases, not a product fix or stable performance proof.
- Large private retry-enter07:17:14.661, timeline-return07:17:23.195, published2/loaded=true07:17:23.198, exit loading=false/errorPresent=false07:17:23.213 (about8.54s). Inspected original recovered private54EAB682-73A9-4880-B9BF-FAA707EC173F.png and room0DC08B16-308E-4D90-9702-12F7407A26C7.png; messages and composer visible. Successful scenario manifest contains PNGs, not a recovery video.
- First large process PID16697: init0.040s, root start-to-return0.580s; bar container(0,866,440,56) appeared07:15:55.427, initial native query07:16:04 returned real button110x56/hittable=true. All8 tab samples passed. No reproduction of C64 initial zero-frame sample.
- First large scheduling probe recorded44 pulses, maxgap55.437s ending07:17:03.303, around conversation navigation; second room process47 pulses/max16.353s. These are sleeping-task execution gaps, NOT a measured main-thread CPU block. No end event; task/process lifecycle, test suspension, host scheduling and instrumentation remain confounders. Do not claim probe proves causality or that diagnostic code repaired stalls.
- Remaining failures checked from raw logs: large actions5 tests/1 failure, group search/menu scenario line144 snapshot timeout; small actions, small layout and small legacy failed AX initialization before scenarios. Large video4 tests/2 failures, including world-tab readiness. OCR same3 controls. Large layout, small video, large legacy, candidate package and H5 jobs succeeded (not all method counts separately audited).
- Both navigation and both composer jobs still running at snapshot; do not cancel or push code. No new code/retry. Overall run cannot pass with existing failures; candidate remains QA-INCOMPLETE. Documentation-only skip-ci record preserves original failed histories and current work.


## C65 final review / C66 report-action diagnostic — 2026-11-18 08:31 UTC
- C65 run44250136745 finished FAILURE; formal package skipped. Large composer4/4 passed; small composer4 tests/1 failure at ChatComposerParityUITests.swift:160 (drive-picker Cancel snapshot query timeout), then original1800s runner budget/30s shutdown timeout. Small navigation logged13/13 assertions but xcodebuild failed to exit within2700s; job cancelled, NOT a passed navigation gate. Large navigation reached11 logged passes, then2700s budget with final case incomplete and unreadable result metadata. Preserve incomplete/timeout distinction.
- Investigated actual large group-report failure rather than assuming an invisible-but-present form. Downloaded original artifact14405640147; original recording C0449A66-743B-4113-ABED-B8F52C144CDF.mp4 retained. Raw test clicked real room.report.room0001 at06:33:19, followed by missing app-idle/animation notifications and report.reason snapshot timeout at line144. Inspected recording near06:39: still group conversation in history context, no report form. Original menu/context/search screenshots and query-chain attachment retained. This establishes no visible form in the inspected recording, not why the action failed.
- Current code protects active/foreground/messages section/no preview, current generation/account and unrecalled exact message snapshot before report action; reporting drives the existing sheet. Existing logs do not reveal whether action guard rejected, state assignment happened, or sheet appeared. Do not weaken protections or insert a presentation delay based on speculation.
- C66 is diagnostic ONLY: App/Infrastructure/RoomReportDiagnostics.swift and DEBUG hooks in App/Features/RoomChatView.swift observe action entry/rejection/acceptance, reporting assignment/change and report sheet onAppear/onDisappear. Rejected flags order: active, foreground, messages section, no preview, same generation, same owner, current unrecalled exact snapshot. Values are fixed stages and booleans plus PID/monotonic uptime, no message IDs/text/accounts/credentials. Enabled only --ui-testing + --chat-align, excluding isolated-backend; cap32/process. No state mutations by diagnostics. Missing/capped/lost events are not proof of failed presentation; sheet callback alone is not screenshot/AX proof.
- scripts/simulator-tests.py exports only the report subsystem for existing chat-alignment-actions shard; missing action-entry or failed export is INCOMPLETE. Existing artifact build/*.json retains capture receipt. scripts/test_room_report_diagnostics.py protects original guard, real tap/form assertions, synthetic/privacy boundaries and collector noninterference.
- Original guard and one perform() call, report payload, sheet presentation logic, all waits/UI tests/thresholds, OCR and concurrency remain unchanged. No warm-up, retry bypass, all-failed rerun or main/PR/release change. Code uses normal CI, not skip ci.
- Local passed: Python151/151, Node2/2, Python compilation, diff check; independent read-only guard/privacy review passed. Swift/Xcode execution unavailable locally; actual build/UI results pending. Refresh no-active-run condition and branch before normal test-branch push.
- Next use actual action/verdict/state/sheet sequence to distinguish rejected stale action from presentation or observation failure, with same-version screenshot/recording. C65 startup scheduling gaps remain unexplained; C66 does not claim to fix them or OCR.

## C66 completed evidence review (2026-11-18 10:42 UTC)
- Code d395bdc1b79a8b4962a15665d80930f47bdfcae8; run https://github.com/qianshou330-cyber/pubo-ios/actions/runs/44267635566 completed FAILURE. No active same-branch run at review; no rerun or product fix made.
- Both actions jobs passed 5/5 with TEST EXECUTE SUCCEEDED (small134677972382, large134677972768). Downloaded original artifacts14415782854/14418861202; both roomreport-capture receipts CAPTURED.
- Each size has five actionEntered -> accepted -> stateAssigned[true] -> statePresent -> sheetAppeared sequences, no rejected events. Historical-message light/dark flows also have stateCleared and sheetDisappeared. Small light09:43:09.008->09:43:09.479 (0.471s), dark09:44:47.478->09:44:49.887 (2.409s); large light10:11:43.857->10:11:46.665 (2.808s), dark10:14:30.601->10:14:32.238 (1.637s). These are callback intervals, not performance guarantees or CPU-block measurements.
- Visually inspected four ORIGINAL report screenshots: small light3AE07700-22DE-4AE3-AE35-4652927B764E.png/dark6929026F-9314-477A-A34E-7C34ACBABC3E.png; large lightB369651C-D7C4-44B0-A23C-4E9DBCDCED68.png/darkE5CCA595-CCB0-4E89-BCF9-6C809332A683.png. All visibly show report form with Cancel/Submit and synthetic room0001 link, consistent with unchanged real tap and original report.reason assertions. No report-test recording in manifest; loading-skeleton.mp4 is NOT report evidence.
- C65 actual tap/no-form failure remains unresolved. C66 only added diagnostic observations, not behavioral repair; one successful run cannot establish cause or stability. Neither stale-snapshot rejection nor sheet failure is demonstrated in this run; do not loosen guards or infer C65 state from C66.
- Other final jobs: both layouts, small states/composer/navigation, large legacy, core/H5 and QA-INCOMPLETE candidate passed. OCR still same3 positives; large navigation2700s and composer1800s exceeded with incomplete results. Small legacy5 tests1 failure. Large states4 tests1 failure at ChatComposerParityUITests.swift:14 message-tab readiness in testLinkPreviewFailurePreservesDestinationAndRetries (not retry-stage failure). Small video4 tests2 failures at initial world-tab readiness. Large video job failed; log download previously BlobNotFound, cause not verified. Formal package skipped; no accepted IPA/release.
- Next: inspect large states/video startup evidence, preserve C65 failure recording and C66 success comparison. Keep bounded diagnostic logging and original protection/budgets; no blind repeated full runs. This update changes documentation only, uses skip ci, and does not mark any issue fixed.

## C66 entry-failure forensic follow-up (2026-11-18, after completed run)
- Downloaded original large-states artifact14417715534 and small-video artifact14417179603; retained original ZIPs/logs/recordings outside repository. No new CI or product patch.
- Large states failure is the SECOND launch in link-preview test (PID36889), not the preceding retry recovery: first launch and independent recovery passed. Both failed readiness samples have valid on-screen110x56 geometry and hittable=false. Window queries0.030/0.037s, frame0.359/0.311s, hit0.738/0.621s. This is NOT the C64 zero-frame/slow-window pattern. Original FC07EE45-79ED-410E-8CC7-D4A30B2DC089.mp4 near end shows message list/loading with visible tabs, no modal. AX debug tree contains selected app.tab.messages button at expected frame.
- Small video missing-thumbnail and untrusted-video cases never passed world-tab entry. Valid94x56 on-screen geometry, all2 and3 samples hittable=false respectively; individual window/frame/hit queries all under0.66s. Original recordings72B4594A-E418-4D2F-A0D5-38A672EA9171.mp4 (near end) and3FB99D61-09CB-497C-90B6-3EC45CD3FDE6.mp4 (18s frame) show normal message list with visible tabs, no visible keyboard/modal. Do not classify these as decoder-policy failures: target world feed was never entered.
- Visible pixels + valid AX frame do NOT prove true hittability. Preserve isHittable requirement; no coordinate fallback, deadline increase or disabled protection. Code inspection of BottomTabBar finds no conditional disabled modifier on tab button; this alone cannot exclude ancestor/hit-test blockers or AX inconsistency.
- Existing startup diagnostics only cover --chat-load-fail-once PIDs20458/26188, NOT failed link-preview PID36889; small-video has no startup probe. Therefore there is no lifecycle trace for these specific failures and no substantiated product root cause yet.
- Next diagnostic should correlate actual failing launch's app scene/window and hit-test responder path using bounded synthetic-only instrumentation (no user content), before making layout/interaction changes. No repair claimed, and C65 report failure remains unresolved.

## C67 synthetic tab hit diagnostics (2026-11-18 11:09 UTC)
- Problem: C66 states/video failures have visible tab pixels and valid AX frames but isHittable=false. No proven behavioral fix. Add bounded same-launch observations, not a repair.
- New App/Infrastructure/TabHitDiagnostics.swift and BottomTabBar background modifier enable only DEBUG + --ui-testing + (--chat-preview-failure or --video-poster-fixture=), excluding isolated backend. Release has no probe. Transparent noninteractive/non-AX UIKit anchor; no layout invalidation, touch dispatch, state/selection mutations or UI-test changes.
- Per process once:30 samples spaced2s, stop before sampling beyond120s or cancellation/removal; maximum8 windows x2 points per sample. Logs start/end/missing geometry/removal markers. Records PID/uptime, scene activation, window key/level/visibility/interaction/alpha, bar-quarter centers and actual UIKit hitTest superclass-category paths capped12 ancestors. No labels, IDs, texts, runtime class names, URLs, user data or tokens.
- Points are BAR quarter centers for messages/world, NOT measured AX button frames. Each scene window is tested independently; levelSortIndex is NOT real equal-level z-order or system touch route. Hit-test outcomes are observational and cannot replace isHittable, rule out AX inconsistencies, or prove CPU blocking. Probe may perturb timing. Anchor replacement can end sampling without restart; missing samples remain incomplete.
- scripts/simulator-tests.py exports tabhit JSON and CAPTURED/INCOMPLETE receipt for states/video only, preserving test_exit and all budgets/guards. Existing workflow includes JSON artifacts; no trigger or acceptance changes.
- Local Python154/154, Node2/2, py_compile and diff check passed. Source equality against remote verified before selective patch. Native Swift compilation/simulator behavior pending CI; Linux cannot validate native hit testing.
- Fresh branch/no-active-run check required before ordinary code push; code must NOT use skip ci. Next compare same-PID trace with failed readiness timestamps and original recordings, retain C66 failures even if new run passes.

## C67 final review (2026-11-18 13:20 UTC)
- Code139b3fca71cf0aca6e6c1e309103988ac9f4c76f, run https://github.com/qianshou330-cyber/pubo-ios/actions/runs/44291986128 finished; full acceptance FAILED, formal package skipped. Both-size layouts/actions, small navigation/composer, large states/video, checks/H5 and QA-INCOMPLETE candidate jobs passed. No release or accepted IPA.
- Verified raw failures: large navigation134761029978 and large composer134761030124 fail AX test-runner initialization (not executed assertion suites). Large legacy134761029914 exceeds1800s, incomplete (one suite assertion passed, not full5). Small legacy134761030049 has5 tests1 failure at AccountSettingsParityUITests.swift:120; small states134761030123 has4 tests1 failure at initial message-tab readiness in recovery test, not recovered-state assertion. OCR remains known3 positives. Do not generalize native infrastructure failures to product feature failure.
- Small video134761030069:4 tests1 failure. Broken-thumbnail PID17378 readiness reports true; genuine world-button tap at12:08:31, synthesized12:08:32.787, then selected-state assertion fails12:08:52.411. Original video5141DF30-D145-44ED-B08C-5EDCD8F04045.mp4 near end still shows message list; this is failed tab transition, before decoder expectations. Missing/server/untrusted cases pass. Preserve immediate post-tap isSelected assertion and genuine click.
- Original small-video artifact14425642964 and large-states14426040799 downloaded; tabhit receipts CAPTURED. All sampled scenes foreground-active, single key visible interactive normal-level window. Failed and successful launches BOTH show scroll/image generic UIKit hit paths, so these categories do not distinguish root cause or prove scroll interception. Samples are bar-quarter centers, not AX activation points; probe timing effects remain possible.
- Large states4/4, including both link-preview launches PID24456/26464 with capture/end markers. Small-video four PIDs17378/18891/21482/23576 captured; process termination can omit end, absence is not proof of blocking. C67 is observation-only, not a fix for C66/C65 intermittent failures.
- Next useful discriminator: synthetic-only capped button-action entry plus selected-tab before/after and independent selected-tab change observation. This would distinguish missing event delivery from state change/reset; current window/hit traces cannot do so. No basis yet for product layout patch, retries or weaker readiness. No new CI launched in this review. Local raw evidence retained under c67-evidence; records contain no credentials or personal data.

## C68 event-delivery / selection diagnostic (2026-11-18 14:26 UTC)
- C67 small-video real tap after hittable=true did not select world. Existing generic hit paths do not explain this. No product fix claimed.
- Minimal addition to TabHitDiagnostics: typed actionEntered/actionReturned/selectionChanged events, capped64 per process. Same DEBUG + synthetic preview/video gating and isolated exclusion as C67. Records only fixed AppTab raw values, PID and uptime; no user text, IDs, tokens, URLs or runtime names.
- BottomTabBar records around its ORIGINAL single conditional assignment. AppSession.selectedTab didSet observes actual distinct old/new values, including assignments outside button. This observer does not mutate state; code outside DEBUG is unchanged behavior. No new polling/touch dispatch/extra waits. Existing tabhit collector retains events; CAPTURED still means sample present, not complete selection coverage.
- Interpret entry missing conservatively (could be missed delivery, cap or log loss); entry+change+return confirms state transition at those instants only. Later selectionChanged back can establish reset but not caller identity. Preserve actual isHittable, real tap and immediate isSelected assertion.
- Local157 Python and2 Node tests pass, diff check clean. Source comparison against current remote passed for all3 edited files. Native @Observable/didSet compilation and UI behavior need CI; no native toolchain locally. This is diagnosis, not repair or stability proof.
- New static contracts scripts/test_tab_selection_diagnostics.py protect cap/privacy, single original assignment, and read-only observer. FIX_LOG and handoff updated; normal code push only after no active same-branch run, no skip ci.

- Independent read-only review found no blocker; @Observable observers supported, no recursive writes. actionReturned.from means requested tab (not prior selection); didSet does not log initial default, and cap/log loss makes absence inconclusive.

## C68 completed evidence review (2026-11-18 16:35 UTC)
- Codeccc9a06b77a2a7fd2c23d93312f6749f3a986063; run https://github.com/qianshou330-cyber/pubo-ios/actions/runs/44324398470 completed. Overall failure; formal package skipped. QA-INCOMPLETE artifact14444221050 is NOT acceptance.
- Confirmed raw logs: small video134873207283, small states134873207344 and large states134873207289 each4/4 and successful test exit. Large video/composer, small legacy, checks/H5/candidate jobs also success.
- Downloaded original small-video14442109751, small-states14444342260, large-states14445251116; all tabhit receipts CAPTURED. Small-video PIDs16113/20296/22388/23564 each show actionEntered messages->world, selectionChanged messages->world, actionReturned world->world. Large-video four equivalent successful chains previously verified. No recorded reset in these traces.
- States preview PIDs30939/33405 small and37407/39847 large show actionEntered messages->messages and actionReturned messages->messages. Absence of selectionChanged here is expected because selected tab was already messages, not missing logging.
- Visually inspected original small broken-video screenshot67D7D889-112A-4CD3-B4C9-096270DF40CA.png: world feed, selected world tab and red decoded video frame are visible. C67 failed to switch; C68 succeeds with observation-only code. No causal repair or stable-root-cause claim justified.
- Remaining failures: large legacy5 tests2 failures (account setting line120 and chat edit conflict line841); small layout5 tests1 failure at initial message-tab readiness. Large navigation/actions and small composer fail AX runner initialization. Small actions runner killed before connection/bootstrap. Small navigation2700s timeout/incomplete. OCR existing failure remains. Large layout failure log unavailable on repeated fetch; no artifact listed, cause unverified. Do not lump all as product assertion failure.
- No product behavior changed or blind rerun started. Keep C65/C66/C67 failures. Current traces show only successful event chains; root cause of intermittent failed tap remains unresolved. Next prioritize a failing trace in the existing scenarios or inspect account-setting failure evidence; do not weaken guard, add coordinate taps, extend budgets, or infer repair from passing candidates.

## C68 recurring privacy-switch failure forensic review (2026-11-18)
- Downloaded original large-legacy artifact14439621349. Failure is FIRST isLocked0->1 on PID19491, not backend save/auto-accept retention. Target attachment37D31093-E130-4AC0-B532-06F021503DF0.txt proves one native switch enabled/hittable with63x28 frame(339,163). Transition attachment17C1FFDF-180E-4C30-BCD8-FCB8138A2A96.txt: before0, tapStarted22.479s, tapReturned23.833s, reads0 at25.520/30.597s; original8s value gate fails.
- Original screenshot0588E8A2-5580-4AF5-B168-B91C8EF60CA3.png visually confirms switch remains OFF and dependent auto-accept disabled. Original video053CF15E-660C-4D4B-9230-85C2E8832F9A.mp4 retained; this review inspected screenshot and logs, not the entire video.
- Existing privacy diagnostic is already sufficient to narrow scope: same PID's isLocked observer attached, control center hit=true and enabled=true from14:50:18; heartbeat samples14:50:38/48/59 and14:51:09 span tap14:50:49 with quotas not exhausted. No setter, native valueChanged/touchUp/touchDown/touchCancel logged for that PID. Do not infer backend rollback: no model mutation recorded. Missing native events is evidence, not absolute proof of missing OS touch delivery.
- Same artifact later PID50189 hideOnlineStatus logs setter true +valueChanged/touchUp and visual/native state true, showing collector can record successful control events. It is a different test/control, not a controlled identical reproduction.
- No justified privacy-model fix yet. No new click probes, threshold changes, synthetic state injection, coordinate fallback, or repeated CI. Next compare identical isLocked success (C68 small legacy) and retained failed recordings before changing control/gesture behavior; inspect existing event delivery versus gesture cancellation hypotheses without declaring root cause.

## C68 identical privacy-control success comparison (2026-11-18)
- Downloaded small legacy14444684946, same codeccc9a06 and same regression selection as large14439621349. Both Xcode26.0.1 build17A400, iOS26.1, x86_64 host, READY boot. Device differs: SE3 vs17 Pro Max; different runners/times are uncontrolled confounders.
- SAME isLocked control succeeds six transitions across light/dark small processes15873/24636:0->1,1->0,0->1 each. All original8s checks complete, first post-tap reads correct. First light target becomes enabled/hit=true16:08:20.889; setter true16:08:42.682375, native valueChanged true+.touchUp true within1ms, native layout on=true follows. Dark repeats same event sequence. Successful traces have NO touchDown records either, so absence of touchDown alone is not diagnostic.
- Large failure PID19491 had matching enabled/hittable and native centerHitsControl=true, same63x28 switch size. Coordinates differ as expected small(282,121), large(339,163); stable before tap. No observed invalid geometry/disabled transition or model rollback distinguishes failure. Both initial loading disabled controls become enabled before testing.
- Small first light native tap duration~2.84s (F051B89C-FA70-43FD-B443-613E03908916.txt) and first post-tap read1; large~1.35s and two reads0. Duration difference is correlation, not proof of required press length or fix; retain ordinary tap and8s budget.
- Narrow conclusion: same model/setter works in successful identical-control cases; failed run does not record reaching setter or valueChanged. Cannot yet separate synthesized touch delivery, native gesture handling, transient layout/AX mismatch or logging gaps. No safe product patch demonstrated, no new probes or CI rerun, no screen-size special case/forced toggle.

## C69 privacy confirmed-draft rebase fix (2026-11-18 16:48 UTC)
- Evidence: deterministic state-flow bug, independent of intermittent switch tap. Initial original A=false/B=false; user editsA=true while remote changes untouchedB=true. First save sends onlyA and confirmed returnsA=true/B=true. Old code updated original only, leaving draftB=false. Next save wrongly sendsB=false, and existing conflict check accepts because freshB==new originalB.
- Fix: only after successful changed-field readback guard, project confirmed onto existing editable draft keys, then advance original before refreshUser await. Both baseline/draft now agree. Failure paths, conflicts, OUTCOME_UNKNOWN confirmation, disabled dependent values, actual taps and original test gates remain unchanged.
- AccountSettingsPolicy.confirmedPrivacyDraft helper deduplicates keys, preserves JSON/null values and excludes unsupported server/account fields. PrivacySettingsView uses Array(values.keys), never wholesale account payload. No extra diagnostics.
- Two Swift regression tests cover remote untouched-field preservation/no false next diff, subsequent deliberate edit, unsupported keys, disabled auto-accept preservation, missing/null and duplicate keys. Two source-contract tests enforce ordering after successful readback and original conflict guard. Local Python159/159 and Node2/2 pass; diff clean. Swift/Xcode not installed locally, new native tests pending normal CI (do not report them passed).
- Source comparison to current remote passed for edited existing files. No active same-branch run before preparation. Normal code commit, no skip ci; no main/PR/release. This fixes post-save local snapshot mismatch, NOT C68 event delivery or all server races; preflight+update is still not atomic across clients.

- Independent read-only patch review found no blocker; verified no await between draft/baseline updates and unchanged conflict/uncertain-result handling. Swift execution remains pending.
