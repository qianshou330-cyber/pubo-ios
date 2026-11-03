# 私信 GIF（0.8.1 / build79）

基于已验收 build78。会话内及原图预览使用原生 SDAnimatedImageView 播放已获准读取的 GIF，保留原帧时长、透明度/处置方式及循环次数；不预解码全部帧。可暂停/继续、点开双指缩放。减少动态或调暗闪烁时默认静态，允许主动播放。

SDWebImage 5.21.7 固定提交 `2de3a496eaf6df9a1312862adcfd54acd73c39c0`，MIT 许可见 SDWebImage-LICENSE.txt（也包含于 App 资源）。仅从现有鉴权 API 返回的 Data 解码，不使用该库的下载器、共享图片缓存或磁盘缓存。

继续使用附件 ID + Bearer 鉴权、禁止重定向、50 MiB 上限。会话帧最长边720像素/缓存8MiB，预览1280像素/缓存16MiB；像素总量超过4000万或超过2000帧的文件不内嵌解码，可保留原文件保存入口。离屏停止动画，离页/换号/进入后台清理内存；恢复前台重新验证读取权限。原有单层引用、编辑撤回、置顶免打扰、语音和保存流程保留。

H5 实际会话缩略图由服务端生成静态 WebP，打开原图才播放 GIF；本轮不修改 H5/backend。配对图使用同一组合成 GIF，必须明确区分缩略图与原图。

CI先完成实际编译再运行同型号 iPhone17 Pro Max、辅助SE3的8项GIF测试、6项社交专项及8项相关回归。新增测试覆盖像素帧变化、暂停/恢复、有限循环、放大/保存取消、减少动态、后台重新鉴权、撤回、换号、静态PNG、超限与损坏文件。当前为源码冻结前的实施记录，实际运行结果与未验项以交付目录验收文件为准。真实 iPhone、iOS17、签名安装/升级及触摸性能不可用模拟器代替。

参考：
- https://github.com/SDWebImage/SDWebImage/tree/5.21.7
- https://developer.apple.com/documentation/imageio/cgimagesourcecreatethumbnailatindex(_:_:_:)

后续构建：`xcodegen generate` 后按 README 构建；CI核对解析的依赖提交。回退到78不修改服务器或任何数据。所有旧包保留。
