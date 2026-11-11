"""Build the native navigation report only from successful groups and their original frame evidence."""
import json
from pathlib import Path
import sys

build = sys.argv[1]
root = Path(__file__).resolve().parent / ("build" + build)
screens = json.loads((root / "native-screenshot-index.json").read_text(encoding="utf8"))
groups = json.loads((root / "native-simulator-groups.json").read_text(encoding="utf8"))
routes = [
    ("reaction", "回应，正文", "0032", "帖子 · 把今晚的歌单留给你。"),
    ("follow", "关注，通知正文", "0031", "个人主页 · @violet"),
    ("mention", "提及，卡片正文", "note.open.notifmention01", "帖子 · @fixture 周末一起听歌吧。"),
    ("reaction:grouped", "聚合回应，正文", "0029", "帖子 · 把今晚的歌单留给你。"),
    ("reaction:grouped", "聚合回应，第二位参与者头像", "notification.actor.noticetest0029.syntheticviolet", "个人主页 · @violet"),
    ("achievementEarned", "取得成就", "0028", "成就"),
    ("chatRoomInvitationReceived", "群聊邀请", "0027", "PUBO 音乐交流"),
    ("reply", "回复，卡片正文", "note.open.notifreply001", "帖子 · 我也在听这一首。"),
    ("renote", "单人转贴，帖文摘要", "0025", "帖子 · 把今晚的歌单留给你。"),
    ("renote:grouped", "多人转贴，正文", "0024", "帖子 · 把今晚的歌单留给你。"),
    ("quote", "引用，卡片正文", "note.open.notifquote001", "帖子 · 这段副歌值得再听一次。"),
    ("note", "用户的新帖子", "0022", "帖子 · 本周的新歌清单更新了。"),
    ("pollEnded", "问卷调查结束", "0021", "帖子 · 周末想听哪种现场？"),
    ("scheduledNotePosted", "定时发送成功", "0020", "帖子 · 午间音乐推荐已送达。"),
    ("scheduledNotePostFailed", "定时发送失败", "0019", "定时帖子"),
    ("receiveFollowRequest", "收到关注请求，打开申请", "0018", "关注申请 · 测试朋友"),
    ("followRequestAccepted", "关注请求已通过", "0017", "个人主页 · @violet"),
    ("app", "关联应用消息，点击文字", "notifications-informational-app-accept", "停留当前筛选，未导航"),
    ("roleAssigned", "授予的角色", "0015", "我的主页 · @fixture"),
    ("exportCompleted", "已完成导出", "0014", "导出文件 · notes-export.json"),
    ("test", "测试通知，点击文字", "notifications-informational-test-accept", "停留当前筛选，未导航"),
    ("login", "账号登录", "0012", "安全验证，通过后进入授权会话与登录记录"),
    ("createToken", "创建访问令牌", "0011", "已授权应用 · 隔离歌单助手（沿用本次安全验证）"),
    ("receiveFollowRequest", "收到关注请求，接受", "notification-follow-accept", "当前通知显示处理结果"),
    ("receiveFollowRequest", "收到关注请求，拒绝", "notification-follow-reject", "当前通知显示处理结果"),
]
wanted = "large/notification-routes"
shots = {r["name"]: r for r in screens if r["group"] == wanted}
group = groups[wanted]
assert group["failed"] == 0 and group["skipped"] == 0 and group["passed"] >= 5, group
header = [f"# PUBO 0.9.4（build {build}）通知页逐类按钮实测", "",
          f"iPhone 17 Pro Max 模拟器，440×956pt，iOS 26.0.1。产品提交 `{group['sourceCommit']}`。",
          "同组模拟数据经正式页面、导航和鉴权界面打开。以下表格记录每次点击后的画面和返回断言。关注申请按钮在模拟界面操作，真实后端回执见独立联调记录。",
          "", "| 类别 | 操作 | 到达位置／结果 | 返回结果 | 原始截图 | 原始录像秒数 |", "|---|---|---|---|---|---|"]
results = []
for kind, action, key, target in routes:
    if key.isdecimal():
        key = "notification-route-notification.noticetest" + key
    elif key.startswith(("note.open", "notification.actor")):
        key = "notification-route-" + key
    row = shots[key]
    back = "列表就地处理" if key.startswith(("notifications-informational", "notification-follow-")) else "回到原筛选，重新定位同一行"
    raw = Path(group["source"]).as_posix()
    when = row["rawVideoSeconds"]
    header.append(f"| `{kind}` | {action} | {target} | {back} | [原图]({row['namedOriginal']}) | [原片 {when:.1f}s]({raw}#t={max(0, when-4):.1f},{when+4:.1f}) |")
    results.append(dict(kind=kind, action=action, target=target, back=back, evidence=row["namedOriginal"], test=row["test"], video=raw, videoSeconds=when))
(root / "原生通知按钮检查表.md").write_text("\n".join(header) + "\n", encoding="utf8")
(root / "native-routes.json").write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf8")
print(len(results), "observed route/button rows")
