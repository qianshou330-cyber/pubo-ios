import SwiftUI
import PUBOCore

struct NotificationRow: View {
    @Environment(AppSession.self) private var session
    @ScaledMetric(relativeTo: .caption) private var textSize = 11.9
    let item: Record
    let requestState: String?
    let respond: (Bool) -> Void
    private var kind: NotificationKind? { NotificationKind(record: item) }
    private var note: Record { Record(item["note"]) }
    private var grouped: Bool { item["type"].string?.hasSuffix(":grouped") == true }
    private var participants: [(user: Record, reaction: String?)] {
        if kind == .reaction { return item["reactions"].array.compactMap {
            let user = Record($0["user"])
            return user.id.isEmpty ? nil : (user, $0["reaction"].string)
        } }
        return Record.list(item["users"]).map { ($0, nil) }
    }
    private var actor: Record? {
        if grouped { return nil }
        switch kind {
        case .pollEnded, .note: return note.user.id.isEmpty ? nil : note.user
        case .roleAssigned, .achievementEarned, .exportCompleted, .login, .createToken, .scheduledNotePosted, .scheduledNotePostFailed: return session.user
        default: return item.user.id.isEmpty ? nil : item.user
        }
    }
    private var header: String {
        if grouped {
            let count = Set(participants.map { $0.user.id }).count
            if kind == .renote { return "\(count) 位用户转贴了你的帖子" }
            return note["reactionAcceptance"].string == "likeOnly" ? "\(count) 位用户喜欢了你的帖子" : "\(count) 位用户回应了你的帖子"
        }
        switch kind {
        case .note: return "新帖子 · " + note.user.displayName
        case .app: return item["header"].string ?? "应用通知"
        case .follow, .receiveFollowRequest, .followRequestAccepted, .renote, .reaction: return item.user.displayName
        case .exportCompleted:
            let entities = ["antenna":"天线", "blocking":"已屏蔽的用户", "clip":"便签", "customEmoji":"自定义表情", "favorite":"收藏", "following":"关注", "muting":"已静音的用户", "note":"帖子", "userList":"列表"]
            return (entities[item["exportedEntity"].string ?? ""] ?? "数据") + "导出完成"
        default: return kind?.title ?? "通知"
        }
    }
    private var summary: String {
        if !note.id.isEmpty { return NoteContext.summary(kind == .renote ? NoteContext.displayed(note) : note) }
        switch kind {
        case .roleAssigned: return item["role"]["name"].string ?? ""
        case .chatRoomInvitationReceived: return item["invitation"]["room"]["name"].string ?? ""
        case .achievementEarned: return NativeStrings.achievement(item["achievement"].string ?? "")
        case .exportCompleted: return "查看文件"
        case .createToken: return "管理访问令牌"
        case .follow: return "你有新的关注者"
        case .followRequestAccepted: return "关注请求已通过" + (item["message"].string.map { " · " + $0 } ?? "")
        case .receiveFollowRequest: return "请求关注你"
        case .test: return "通知会像这样显示"
        case .app: return item["body"].string ?? ""
        default: return ""
        }
    }
    private var icon: String {
        switch kind {
        case .follow, .reaction: "plus"
        case .receiveFollowRequest: "clock"
        case .followRequestAccepted: "checkmark"
        case .renote: "repeat"
        case .pollEnded: "chart.bar"
        case .scheduledNotePosted: "paperplane"
        case .scheduledNotePostFailed: "exclamationmark.triangle"
        case .roleAssigned: "rosette"
        case .chatRoomInvitationReceived: "bubble.left.and.bubble.right"
        case .achievementEarned: "medal"
        case .exportCompleted: "archivebox"
        case .login: "arrow.right.to.line"
        case .createToken: "key"
        default: "bell"
        }
    }
    private var badgeColor: Color {
        switch kind {
        case .follow, .receiveFollowRequest, .followRequestAccepted: PUBOTheme.adaptive(0x36aed2, 0x36aed2)
        case .renote: PUBOTheme.adaptive(0x36d298, 0x36d298)
        case .achievementEarned, .reaction: PUBOTheme.adaptive(0xcc9815, 0xe99a0b)
        case .login: .blue
        default: PUBOTheme.adaptive(0x88a6b7, 0x88a6b7)
        }
    }
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            avatar
            VStack(alignment: .leading, spacing: 0) {
                if let actor, !item.user.id.isEmpty && !grouped && actor.id == item.user.id && (kind == .renote || kind == .reaction || kind == .receiveFollowRequest) {
                    HStack(alignment: .firstTextBaseline) {
                        NavigationLink { ProfileView(userID: actor.id) } label: { Text(header).lineLimit(1) }
                            .accessibilityIdentifier("notification.name." + item.id)
                        Spacer(minLength: 4)
                        time
                    }
                    primaryLink { summaryLabel.frame(maxWidth: .infinity, minHeight: 28, alignment: .leading) }
                } else {
                    primaryLink {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(alignment: .firstTextBaseline) { Text(header).lineLimit(2); Spacer(minLength: 3); time }
                            if !summary.isEmpty { summaryLabel }
                        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
                    }
                }
                if grouped {
                    ChatReactionFlow {
                        ForEach(Array(participants.enumerated()), id: \.offset) { _, part in
                            NavigationLink { ProfileView(userID: part.user.id) } label: {
                                Avatar(user: part.user, size: 38).overlay(alignment: .bottomTrailing) {
                                    if let reaction = part.reaction { reactionBadge(reaction) }
                                }.frame(width: 44, height: 44)
                            }.accessibilityLabel(part.user.displayName).accessibilityIdentifier("notification.actor." + item.id + "." + part.user.id)
                        }
                    }.padding(.top, 4)
                }
                if kind == .receiveFollowRequest && !item.user.id.isEmpty {
                    if let requestState { Text(requestState).foregroundStyle(.secondary).padding(.vertical, 6) }
                    else {
                        HStack(spacing: 8) {
                            Button { respond(true) } label: { Label("接受", systemImage: "checkmark") }
                                .buttonStyle(PUBOButtonStyle(kind: .primary)).accessibilityIdentifier("notification.accept." + item.id)
                            Button { respond(false) } label: { Label("拒绝", systemImage: "xmark") }
                                .buttonStyle(PUBOButtonStyle()).accessibilityIdentifier("notification.reject." + item.id)
                        }.padding(.top, 6)
                    }
                }
            }
        }.font(.system(size: textSize)).buttonStyle(.plain)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(PUBOTheme.panel)
    }
    private var time: some View {
        Group {
            if let date = puboDate(item["createdAt"].string) {
                ChatRelativeTime(date: date).font(.system(size: textSize * 0.9)).foregroundStyle(PUBOTheme.secondary).fixedSize(horizontal: true, vertical: false)
            }
        }
    }
    private var summaryLabel: some View {
        Text(summary).lineLimit(kind == .app ? nil : 2).foregroundStyle(PUBOTheme.secondary)
    }
    @ViewBuilder private func primaryLink<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if NotificationTarget.resolve(item) == .none {
            content().accessibilityElement(children: .combine).accessibilityIdentifier("notification.text." + item.id)
        } else {
            NavigationLink { NotificationDestinationView(item: item) } label: { content().contentShape(Rectangle()) }
                .accessibilityIdentifier("notification." + item.id)
        }
    }
    @ViewBuilder private var avatar: some View {
        if let actor {
            NavigationLink { ProfileView(userID: actor.id) } label: {
                Avatar(user: actor, size: 42).overlay(alignment: .bottomTrailing) {
                    if kind == .reaction, let reaction = item["reaction"].string { reactionBadge(reaction) }
                    else if kind == .roleAssigned, let url = safeMediaURL(item["role"]["iconUrl"].string) {
                        AsyncImage(url: url) { $0.resizable().scaledToFit() } placeholder: { Color.clear }.frame(width: 20, height: 20)
                    } else if kind != .note { badge }
                }.frame(width: 44, height: 44).contentShape(Rectangle())
            }.accessibilityLabel(actor.displayName).accessibilityIdentifier("notification.actor." + item.id)
        } else if grouped {
            Image(systemName: kind == .reaction && note["reactionAcceptance"].string == "likeOnly" ? "heart.fill" : icon)
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 34, height: 34).background(badgeColor, in: Circle())
                .frame(width: 44, height: 44, alignment: .topLeading).accessibilityHidden(true)
        } else if let url = safeMediaURL(item["icon"].string) {
            AsyncImage(url: url) { $0.resizable().scaledToFit() } placeholder: { Color.clear }
                .frame(width: 42, height: 42).clipShape(RoundedRectangle(cornerRadius: 6)).accessibilityHidden(true)
        } else { Color.clear.frame(width: 44, height: 44).accessibilityHidden(true) }
    }
    private var badge: some View {
        Image(systemName: icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
            .frame(width: 20, height: 20).background(badgeColor, in: Circle())
            .overlay(Circle().stroke(PUBOTheme.panel, lineWidth: 2))
    }
    private func reactionBadge(_ value: String) -> some View {
        ReactionImage(reaction: value, emojis: note["reactionEmojis"], emojiHeight: 18, unicodeSize: 15)
            .frame(width: 20, height: 20).background(PUBOTheme.panel, in: Circle())
    }
}
