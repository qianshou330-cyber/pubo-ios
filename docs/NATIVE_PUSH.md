# 原生锁屏推送交接

当前状态：App 和后端已实现候选，真实 APNs 通道保持关闭。未签名 IPA、模拟器结果与真实 iPhone 锁屏投递是不同验收项。

## 接口与设备生命周期

- `native-push/register`、`native-push/unregister` 使用本人现有授权，要求通知写权限；登记还核对通知读权限。聊天投递另核对聊天读权限。
- 每次操作携带安装 UUID、递增 revision、环境和固定 bundle ID。服务端按安装及账号保留注销次序；关闭、退出和换号后的迟到登记不能重新启用旧订阅。
- 退出会立即清理本机通知并尝试注销服务器登记，结果不确定时不自动重新开启。令牌变更及恢复前台会重新核对登记；设备租约为 30 天。
- 推送载荷只含通用提醒和账号／事件标识。点击后重新鉴权读取正文和附件；前台使用原实时连接，避免重复弹出锁屏提醒。
- 发送前复核授权、账号状态、双向拉黑、私信拉黑、免打扰、已读及撤回；失效设备停止发送，临时错误有限退避。

## 后端配置

新增配置默认不填写，即关闭；`/api/meta` 返回 `nativePushAvailable: false`。本轮只追加 `native_push_subscription` 表，不修改数据库或 Redis 服务配置。配置字段如下，示例不含有效身份或密钥：

```yaml
nativePush:
  enabled: false
  environment: production
  bundleId: com.bolubo.native
  teamId: APPLE_TEAM_ID
  keyId: APPLE_KEY_ID
  privateKeyFile: /run/secrets/pubo-apns.p8
```

私钥文件仅放服务器受限路径，限制为服务运行者可读，Unix 权限不大于 `0600`；不得放入仓库、源码包、App、公开日志。启用前必须使用真实开发者资料替换示例，并完成签名与设备测试。

## 签名及设备验收

工程 Debug 使用 development，Release 使用 production；`PUBOAPNSEnvironment` 与签名的 `aps-environment` 必须一致。使用开发签名时，应重新构建对应环境，不只改服务器设置。

待有开发者账号后完成：应用标识与推送能力、匹配的签名配置、真机权限拒绝／允许、前后台、锁屏点击、令牌更新、关闭／重新开启、退出／换号、撤权、免打扰和撤回。只有真实验收通过后再开启服务器能力。公开政策和 App Store 隐私披露也须随实际启用范围更新。

当前没有签名、密钥或真实投递证据，不承诺后台持续联网，不把普通网页推送当成原生 APNs。
