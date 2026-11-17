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
