# 架构与接口边界

App 为 iOS 17+ SwiftUI 界面，PUBOCore 为 Foundation Swift Package。没有第三方客户端运行依赖；XcodeGen 只用于生成工程。

## 连接及账号

仅连接 `https://bolubo.com/api/`，凭据不会随外站图片或原文链接发送。网络层拒绝认证请求重定向；密码不保存，登录令牌只进入 `WhenUnlockedThisDeviceOnly` Keychain。一个安装同时使用一个账号。

原生登录使用 **`signin-flow`**，支持密码与 TOTP；不是旧版 `signin` 路由。短信注册使用 `signup/request-phone-code` 和 `signup`。根据 meta 显示邀请码、邮箱与安全验证要求；需要网页验证码或通行密钥时使用系统授权窗口与 MiAuth，校验随机 session 回调。不会在 App 内绕过验证码。

## 接口索引

| 模块 | 现有接口 |
|---|---|
| 动态 | notes/home-timeline、local-timeline、global-timeline、show、replies |
| 发帖与反应 | notes/create、notes/reactions/create、delete；drive/files/create |
| 通知 | i/notifications、notifications/mark-all-as-read |
| 个人资料 | users/show、notes、following、followers、search；i/update |
| 安全 | following/create、delete；blocking/create、delete；users/report-abuse；i/delete-account |
| 私信 | chat/conversations、conversation-settings/update、messages/user-timeline、create-to-user、read |
| 私密附件 | chat/attachments/create；GET chat/attachments/{id}/original，Authorization Bearer |

普通发帖不传空 `fileIds`（该字段存在时至少一项）；纯文字私信使用空 `attachmentIds` 合法。私信不使用旧 `fileId` 或公开网盘附件冒充私密附件。

## 发送可靠性

普通帖子没有本站幂等请求字段。发送前持久保存草稿状态，验证作者、正文、可见范围、引用和有序附件回执后才清除；网络中断、5xx 或异常成功响应保留“不确定”状态，停止再次提交，由用户核对记录后决定。

私信先保存固定 `clientMessageId` 再发送。第二条限制显示服务器业务错误，只保留本机待发内容，不创建系统消息。重启将 sending 恢复为 uncertain；用户点击核对后，从请求时间附近分页查找，核对 client ID、作者、收件人（返回时）、正文、引用及有序附件。扫描不完整时不重发；完整扫描未找到时仅用原 client ID 手动重试。收到回复不会自动发送积压消息。待发记录保留 24 小时。

图片、视频和文件单项客户端上限 50 MB，服务器可以进一步拒绝。公开帖子最多 16 项，私信最多 10 项。语音使用本机录制，最长 60 秒，再经本站语音附件接口处理。上传结果不确定不会自动重试或删除服务器文件。

## 实时与缓存

前台使用本站 WSS，凭据在 Authorization 头中。main 加当前可见时间线或 chatUser 通道；断线 1–60 秒退避重连，恢复后重新取列表按 ID 合并。退到后台关闭连接，不提供后台持续在线或锁屏通知。

公开媒体 URLCache 内存 16 MB、磁盘 64 MB；每个时间线仅缓存最新 100 条公开帖子，最多 24 小时，缓存与私信待发文件位于不同账号目录。表情异步读取，失败不阻塞账号或正文。单页最多保留 2000 条动态/聊天记录，历史详情可通过本站网页继续查看。

私信附件使用无缓存认证请求，预览和录音临时文件具有完整文件保护；退出、关闭预览与下次启动清理本 App 临时文件。本机草稿目录排除备份。退出清 Keychain、账号草稿/待发缓存和公开 URLCache；不清服务器数据。

## 明确范围

四个主页面为原生界面。复杂 MFM、投票、完整安全设置、政策与原文通过系统浏览器打开。首版无 APNs、榜单、游戏、管理员后台、历史积分或多账号。后端业务、数据库结构、生产服务不改动。
