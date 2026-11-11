import SwiftUI
import PUBOCore

struct NotificationDestinationView: View {
    @Environment(AppSession.self) private var session
    let item: Record
    var body: some View {
        switch NotificationTarget.resolve(item) {
        case .note(let id): NoteDetailView(noteID: id)
        case .user(let id): ProfileView(userID: id)
        case .room(let id): RoomChatView(roomID: id)
        case .file(let id): NotificationFileView(fileID: id)
        case .achievements: AchievementsView()
        case .sessions: AdminGate(management: false) { AuthorizedSessionsView() }
        case .connections: AdminGate(management: false) { AuthorizedSessionsView(appsOnly: true) }
        case .followRequests: FollowRequestsView()
        case .scheduled: ScheduledNotesView()
        case .profile:
            if let user = session.user { ProfileView(userID: user.id) }
        case .none: Text("此通知没有可打开的内容，或内容已不可用。").padding().puboScreen().navigationTitle("通知详情")
        }
    }
}

/// Resolve a file by its authenticated ID. Never accept a download URL supplied by a notification.
private struct NotificationFileView: View {
    @Environment(AppSession.self) private var session
    let fileID: String
    @State private var file: Record?
    @State private var error: String?
    @State private var preview: Record?
    @State private var retry = 0
    var body: some View {
        List {
            if let file {
                Label(file["name"].string ?? "导出文件", systemImage: "doc.zipper")
                Button("查看与保存导出文件") { preview = file }.frame(minHeight: 44)
            } else if let error { ErrorBanner(message: error) { retry += 1 } }
            else { ProgressView("读取导出文件…") }
        }.puboList().navigationTitle("导出文件")
            .task(id: retry) {
                let owner = session.generation
                do {
                    let result = Record(try await session.call("drive/files/show", ["fileId": .string(fileID)]))
                    guard owner == session.generation, !Task.isCancelled else { return }
                    guard result.id == fileID else { throw APIError.invalidResponse }; file = result; error = nil
                } catch { if owner == session.generation && !Task.isCancelled { self.error = error.localizedDescription } }
            }.sheet(item: $preview) { PublicAttachmentPreview(file: $0) }
            .onDisappear { preview = nil }
    }
}
