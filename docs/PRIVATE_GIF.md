# 私信 GIF（0.8.1 / build84）

基于已验收 build78。按用户最新要求，会话内及原图预览加载成功后自动播放，不显示 GIF 标识、暂停或播放按钮；点图打开原图并可双指缩放。使用原生 SDAnimatedImageView 播放已获准读取的 GIF，保留原帧时长、透明度/处置方式及循环次数，不预解码全部帧。界面减少动态选项不将 GIF 文件变为静态，与 H5 原图行为一致；离屏/后台停止并清理，回到前台重新鉴权后自动播放。其他界面的减少动态支持不变。

SDWebImage 5.21.7 固定提交 `2de3a496eaf6df9a1312862adcfd54acd73c39c0`，MIT 许可见 SDWebImage-LICENSE.txt（也包含于 App 资源）。仅从现有鉴权 API 返回的 Data 解码，不使用该库的下载器、共享图片缓存或磁盘缓存。

继续使用附件 ID + Bearer 鉴权、禁止重定向、50 MiB 上限。会话帧最长边720像素/缓存8MiB，预览1280像素/缓存16MiB；像素总量超过4000万或超过2000帧的文件不内嵌解码，可保留原文件保存入口。离屏停止动画，离页/换号/进入后台清理内存；恢复前台重新验证读取权限。原有单层引用、编辑撤回、置顶免打扰、语音和保存流程保留。

H5 实际会话缩略图由服务端生成静态 WebP，打开原图才播放 GIF；本轮不修改 H5/backend。配对图使用同一组合成 GIF，必须明确区分缩略图与原图。

有限循环按浏览器语义核对：缺少循环扩展播放一次，0 无限循环，文件中的正数 N 表示首次播放后再重复 N 次。iOS ImageIO 已将该字段换算为总播放次数，因此直接使用固定解码器结果，不能再次加一。UI 专项使用 loop=1 的文件核对结束时累计播放两轮，不因视图刷新自行重启。

CI先完成实际编译再运行同型号 iPhone17 Pro Max、辅助SE3的8项GIF测试、6项社交专项及8项相关回归。新增测试覆盖自动播放及无额外控制栏、有限循环、放大/保存取消、后台重新鉴权/自动恢复、撤回、换号、静态PNG、超限与损坏文件。当前为源码冻结前的实施记录，实际运行结果与未验项以交付目录验收文件为准。真实 iPhone、iOS17、签名安装/升级及触摸性能不可用模拟器代替。

参考：
- https://github.com/SDWebImage/SDWebImage/tree/5.21.7
- https://developer.apple.com/documentation/imageio/cgimagesourcecreatethumbnailatindex(_:_:_:)
- https://chromium.googlesource.com/chromium/src/+/42b474cc4899601a878d04b6c9245737b81cf231/third_party/blink/renderer/platform/image-decoders/webp/webp_image_decoder.cc (GIF repetition count uses N + 1 cycles)

后续构建：`xcodegen generate` 后按 README 构建；CI核对解析的依赖提交。回退到78不修改服务器或任何数据。所有旧包保留。
