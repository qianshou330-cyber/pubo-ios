import Foundation
import PUBOCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class StreamRedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

@MainActor final class StreamClient {
    var onChange: (() -> Void)?
    var onConnect: (() -> Void)?
    var onChatEvent: ((String) -> Void)?
    var onChatMessageEvent: ((ChatStreamEvent) -> Void)?
    var onTimelineNote: ((Record) -> Void)?
    var onNoteEvent: ((NoteStreamEvent) -> Void)?
    var onNotificationEvent: ((String, JSONValue) -> Void)?
    private var task: Task<Void, Never>?
    private var socket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var currentToken: String?
    private var notificationTask: Task<Void, Never>?
    private var timeline: String?
    private var timelineParameters: [String: JSONValue] = [:]
    private var timelineChannelID = "timeline-" + UUID().uuidString
    private var captured = Set<String>()
    private var captureOwners: [String: Set<String>] = [:]
    private var peerID: String?
    private var roomID: String?

    func showTimeline(_ name: String?, parameters: [String: JSONValue] = [:]) {
        guard timeline != name || timelineParameters != parameters else { return }
        let old = timelineChannelID
        timeline = name; timelineParameters = parameters; timelineChannelID = "timeline-" + UUID().uuidString
        guard let socket else { return }
        let id = timelineChannelID
        Task {
            try? await send(.object(["type": .string("disconnect"), "body": .object(["id": .string(old)])]), socket: socket)
            if let name, id == timelineChannelID, self.socket === socket, peerID == nil, roomID == nil {
                try? await send(.object(["type": .string("connect"), "body": .object(["channel": .string(name + "Timeline"), "id": .string(id), "params": .object(parameters)])]), socket: socket)
            }
        }
    }
    func captureNotes(_ ids: Set<String>, owner: String = "timeline") {
        if ids.isEmpty { captureOwners.removeValue(forKey: owner) } else { captureOwners[owner] = ids }
        let next = Set(captureOwners.values.reduce(into: Set<String>()) { $0.formUnion($1) }.sorted().suffix(90)); let removed = captured.subtracting(next); let added = next.subtracting(captured)
        captured = next
        guard let socket else { return }
        Task {
            for id in removed { try? await send(.object(["type": .string("un"), "body": .object(["id": .string(id)])]), socket: socket) }
            for id in added { try? await send(.object(["type": .string("sr"), "body": .object(["id": .string(id)])]), socket: socket) }
        }
    }
    func clearAllCaptures() { captureOwners = [:]; captureNotes([]) }
    func readVisibleNotifications() {
        guard let socket else { return }
        Task {
            guard self.socket === socket else { return }
            try? await send(.object(["type": .string("readNotification")]), socket: socket)
        }
    }
    private func send(_ packet: JSONValue, socket: URLSessionWebSocketTask) async throws {
        try await socket.send(.data(try JSONEncoder().encode(packet)))
    }
    func showChat(_ id: String?) {
        guard peerID != id else { return }
        peerID = id; roomID = nil; reconnectForContext()
    }
    func showRoom(_ id: String?) { guard roomID != id else { return }; roomID = id; peerID = nil; reconnectForContext() }
    private func reconnectForContext() {
        guard let token = currentToken else { return }
        stop(); start(token: token)
    }

    func start(token: String) {
        guard currentToken != token || task == nil else { return }
        stop(); currentToken = token
        task = Task { [weak self] in
            var backoff: UInt64 = 1
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    var request = URLRequest(url: URL(string: "wss://bolubo.com/streaming")!)
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--isolated-backend") { request.url = URL(string: "ws://127.0.0.1:61812/streaming")! }
                    #endif
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    let config = URLSessionConfiguration.ephemeral
                    config.urlCache = nil
                    config.httpCookieStorage = nil
                    config.timeoutIntervalForRequest = 20
                    let session = URLSession(configuration: config, delegate: StreamRedirectGuard(), delegateQueue: nil)
                    self.session = session
                    let socket = session.webSocketTask(with: request)
                    self.socket = socket; socket.resume()
                    var channels: [(String, [String: JSONValue])] = [("main", [:])]
                    if let peer = self.peerID { channels.append(("chatUser", ["otherId": .string(peer)])) }
                    else if let room = self.roomID { channels.append(("chatRoom", ["roomId": .string(room)])) }
                    else if let timeline = self.timeline, ["home", "local", "hybrid", "global"].contains(timeline) { channels.append((timeline + "Timeline", self.timelineParameters)) }
                    for (channel, parameters) in channels {
                        let packet: JSONValue = .object(["type": .string("connect"), "body": .object(["channel": .string(channel), "id": .string(channel.hasSuffix("Timeline") ? self.timelineChannelID : channel), "params": .object(parameters)])])
                        try await socket.send(.data(try JSONEncoder().encode(packet)))
                    }
                    for id in self.captured { try await self.send(.object(["type": .string("sr"), "body": .object(["id": .string(id)])]), socket: socket) }
                    self.onConnect?(); self.notify()
                    while !Task.isCancelled {
                        let message = try await socket.receive()
                        guard !Task.isCancelled, self.socket === socket else { return }
                        let data: Data
                        switch message { case .data(let value): data = value; case .string(let value): data = Data(value.utf8); @unknown default: continue }
                        guard let packet = try? JSONDecoder().decode(JSONValue.self, from: data) else { continue }
                        if packet["type"].string == "noteUpdated", let id = packet["body"]["id"].string, let kind = packet["body"]["type"].string {
                            self.onNoteEvent?(.init(id: id, kind: kind, body: packet["body"]["body"]))
                        } else if packet["type"].string == "channel" {
                            backoff = 1
                            if packet["body"]["id"].string == self.timelineChannelID {
                                if packet["body"]["type"].string == "note" { self.onTimelineNote?(Record(packet["body"]["body"])) }
                                continue
                            }
                            if packet["body"]["id"].string?.hasPrefix("timeline-") == true { continue }
                            if packet["body"]["id"].string == "main", let kind = packet["body"]["type"].string,
                               ["notification", "notificationFlushed", "readAllNotifications", "unreadNotification"].contains(kind) {
                                self.onNotificationEvent?(kind, packet["body"]["body"])
                            }
                            if let channel = packet["body"]["id"].string, ["chatUser", "chatRoom"].contains(channel),
                               let target = channel == "chatRoom" ? self.roomID : self.peerID,
                               let kind = packet["body"]["type"].string {
                                self.onChatMessageEvent?(.init(room: channel == "chatRoom", targetID: target, kind: kind, body: packet["body"]["body"]))
                            }
                            if packet["body"]["id"].string == "chatUser" {
                                let event = packet["body"]["body"]
                                if let id = event["messageId"].string ?? event["id"].string { self.onChatEvent?(id) }
                                for id in event["messageIds"].array.compactMap(\.string) { self.onChatEvent?(id) }
                            }
                            self.notify()
                        }
                    }
                } catch {
                    // A cancelled old task must never close a replacement connection.
                    if Task.isCancelled { return }
                    self.socket?.cancel(with: .goingAway, reason: nil)
                    self.session?.invalidateAndCancel()
                    try? await Task.sleep(nanoseconds: backoff * 1_000_000_000)
                    backoff = min(backoff * 2, 60)
                }
            }
        }
    }
    func stop() {
        notificationTask?.cancel(); notificationTask = nil
        task?.cancel(); task = nil; currentToken = nil
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
        session?.invalidateAndCancel(); session = nil
    }
    private func notify() {
        guard notificationTask == nil else { return }
        notificationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.onChange?(); self?.notificationTask = nil
        }
    }
}
