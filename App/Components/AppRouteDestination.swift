import SwiftUI
import PUBOCore

struct AppRouteDestination: View {
    let route: AppRoute
    var body: some View {
        Group { switch route {
        case .chat(let userID): RoutedChatView(userID: userID)
        case .room(let id): RoomChatView(roomID: id)
        case .note(let id): NoteDetailView(noteID: id)
        case .notifications: NotificationsView()
        case .followRequests: FollowRequestsView()
        } }.id(route)
    }
}

private struct RoutedChatView: View {
    @Environment(AppSession.self) private var session
    let userID: String
    @State private var peer: Record?
    @State private var error: String?
    @State private var requestID = UUID()
    var body: some View {
        Group {
            if let peer { ChatView(peer: peer) }
            else if let error { ErrorBanner(message: error) { Task { await load() } } }
            else { ProgressView("读取会话…") }
        }.task(id: session.generation.uuidString + userID) { await load() }
    }
    private func load() async {
        let generation = session.generation, attempt = UUID()
        requestID = attempt; error = nil; peer = nil
        do {
            let value = Record(try await session.call("users/show", ["userId": .string(userID)]))
            try Task.checkCancellation()
            guard requestID == attempt, session.generation == generation else { return }
            guard value.id == userID else { throw APIError.invalidResponse }
            peer = value
        } catch { if !Task.isCancelled, requestID == attempt, session.generation == generation { self.error = error.localizedDescription } }
    }
}
