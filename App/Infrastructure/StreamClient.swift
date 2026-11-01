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
    private var task: Task<Void, Never>?
    private var socket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var currentToken: String?
    private var notificationTask: Task<Void, Never>?
    private var timeline: String? = "home"
    private var peerID: String?

    func showTimeline(_ name: String?) {
        guard timeline != name else { return }
        timeline = name; reconnectForContext()
    }
    func showChat(_ id: String?) {
        guard peerID != id else { return }
        peerID = id; reconnectForContext()
    }
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
                    else if let timeline = self.timeline, ["home", "local", "hybrid", "global"].contains(timeline) { channels.append((timeline + "Timeline", [:])) }
                    for (channel, parameters) in channels {
                        let packet: JSONValue = .object(["type": .string("connect"), "body": .object(["channel": .string(channel), "id": .string(channel), "params": .object(parameters)])])
                        try await socket.send(.data(try JSONEncoder().encode(packet)))
                    }
                    self.onConnect?(); self.notify()
                    while !Task.isCancelled {
                        let message = try await socket.receive()
                        let data: Data
                        switch message { case .data(let value): data = value; case .string(let value): data = Data(value.utf8); @unknown default: continue }
                        if let packet = try? JSONDecoder().decode(JSONValue.self, from: data), packet["type"].string == "channel" {
                            backoff = 1
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
