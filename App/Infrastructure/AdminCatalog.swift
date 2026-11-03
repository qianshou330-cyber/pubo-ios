import Foundation
import PUBOCore

struct AdminCatalog: Decodable {
    let endpoints: [AdminEndpoint]
    static let shared: AdminCatalog? = {
        guard let url = Bundle.main.url(forResource: "AdminCatalog", withExtension: "json"), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AdminCatalog.self, from: data)
    }()
    func endpoint(_ id: String) -> AdminEndpoint? { endpoints.first { $0.id == id } }
    static func group(_ id: String) -> String {
        if id.contains("verification/") { return "认证审批" }
        if id.contains("announcements/") { return "公告" }
        if id.contains("emoji") { return "表情" }
        if id.contains("avatar-decorations/") { return "头像装饰" }
        if id.contains("roles/") { return "角色与权限" }
        if id.contains("queue/") { return "任务队列" }
        if id.contains("relays/") { return "中继" }
        if id.contains("invite/") { return "邀请" }
        if id.contains("/ad/") || id.contains("/promo/") { return "广告与推广" }
        if id.contains("drive/") || id.contains("-file") { return "媒体文件" }
        if id.contains("system-webhook/") || id.contains("notification-recipient/") { return "系统通知" }
        if id.contains("abuse-") { return "举报" }
        if id.contains("federation/") { return "联邦" }
        if id.contains("moderation-logs") { return "审核日志" }
        if id.contains("user") || id.contains("accounts/") || ["admin/delete-account", "admin/reset-password", "admin/unset-mfa"].contains(id) { return "用户" }
        if ["admin/meta", "admin/update-meta", "admin/send-email", "admin/captcha/current", "admin/captcha/save", "admin/update-proxy-account"].contains(id) { return "站点配置" }
        return "概览与统计"
    }
    static func title(_ id: String) -> String {
        let special: [String: String] = ["admin/show-users":"用户列表", "admin/show-user":"用户详情", "admin/accounts/create":"创建用户", "admin/accounts/delete":"删除用户（账号接口）", "admin/accounts/find-by-email":"按邮箱查找", "admin/delete-account":"删除账号", "admin/reset-password":"重置密码", "admin/unset-mfa":"移除两步验证", "admin/suspend-user":"封禁用户", "admin/unsuspend-user":"解除封禁", "admin/unset-user-avatar":"清除头像", "admin/unset-user-banner":"清除背景图", "admin/delete-all-files-of-a-user":"清除用户全部文件", "admin/get-user-ips":"查看登录地址", "admin/update-user-note":"修改管理备注", "admin/meta":"查看站点配置", "admin/update-meta":"修改站点配置", "admin/update-proxy-account":"修改代理账号介绍", "admin/send-email":"发送测试邮件", "admin/show-moderation-logs":"审核日志", "admin/abuse-user-reports":"举报列表", "admin/resolve-abuse-user-report":"处理举报", "admin/forward-abuse-user-report":"转发举报", "admin/update-abuse-user-report":"更新举报处理人", "admin/queue/queues":"全部队列", "admin/queue/jobs":"任务列表", "admin/queue/queue-stats":"队列统计", "admin/queue/show-job":"任务详情", "admin/queue/show-job-logs":"任务日志", "admin/queue/retry-job":"重试任务", "admin/queue/remove-job":"删除任务", "admin/queue/promote-jobs":"提前执行延迟任务", "admin/queue/deliver-delayed":"延迟发送", "admin/queue/inbox-delayed":"延迟收件", "admin/drive/files":"媒体列表", "admin/drive/show-file":"媒体详情", "admin/drive/clean-remote-files":"清理远程媒体", "admin/drive/cleanup":"清理未引用媒体", "admin/roles/update-default-policies":"默认角色策略", "admin/roles/users":"角色成员", "admin/roles/assign":"分配角色", "admin/roles/unassign":"移除角色", "admin/federation/delete-all-files":"清理实例媒体", "admin/federation/remove-all-following":"解除实例关注关系", "admin/federation/update-instance":"更新实例设置", "admin/federation/refresh-remote-instance-metadata":"刷新实例资料", "stats":"站点统计", "get-online-users-count":"在线人数", "admin/server-info":"服务器信息", "server-info":"服务器状态", "admin/get-table-stats":"数据表统计", "admin/get-index-stats":"索引统计", "retention":"留存统计", "federation/instances":"联邦实例", "federation/show-instance":"实例详情", "federation/update-remote-user":"刷新远程用户", "export-custom-emojis":"导出表情", "admin/emoji/import-zip":"导入表情包", "admin/emoji/copy":"复制远程表情", "admin/emoji/list-remote":"远程表情", "admin/emoji/add-aliases-bulk":"批量添加别名", "admin/emoji/remove-aliases-bulk":"批量移除别名", "admin/emoji/set-aliases-bulk":"批量设置别名", "admin/emoji/set-category-bulk":"批量设置分组", "admin/emoji/set-license-bulk":"批量设置许可", "admin/emoji/delete-bulk":"批量删除表情", "admin/captcha/current":"验证服务状态", "admin/captcha/save":"设置验证服务", "charts/users":"用户变化", "charts/notes":"帖子变化", "charts/active-users":"活跃用户", "charts/ap-request":"联邦请求"]
        if let label = special[id] { return label }
        let action = id.split(separator: "/").last.map(String.init) ?? id
        return ["create":"创建", "list":"列表", "show":"查看详情", "update":"修改", "delete":"删除", "add":"添加", "remove":"移除", "approve":"通过认证", "reject":"拒绝申请", "revoke":"撤销认证", "document":"查看受保护材料", "pause":"暂停", "resume":"恢复", "clear":"清空", "stats":"统计", "test":"发送测试事件", "users":"成员"][action] ?? action
    }
}
