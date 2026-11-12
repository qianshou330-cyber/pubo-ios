import SwiftUI
import UserNotifications
import PUBOCore

@MainActor final class NativeAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { await NativePushController.shared.receivedToken(token) }
    }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NativePushController.shared.status = "设备推送注册未完成，请检查签名、通知权限和网络。"
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // The foreground UI uses the authenticated stream, not a second lock-screen alert.
        completionHandler([])
        Task { @MainActor in NativePushController.shared.foregroundUpdate() }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let data = try? JSONSerialization.data(withJSONObject: response.notification.request.content.userInfo)
        completionHandler()
        guard let data, let payload = try? JSONDecoder().decode(JSONValue.self, from: data), let notice = NativePushNotice(payload) else { return }
        Task { @MainActor in await NativePushController.shared.open(notice) }
    }
}

@Observable @MainActor final class NativePushController {
    static let shared = NativePushController()
    weak var session: AppSession?
    var status = "锁屏推送尚未开放。"
    private(set) var enabled = false
    private(set) var busy = false
    private var deviceToken: String?
    private var registeredOwner: String?
    private var registeredToken: String?
    private var registeredDeviceToken: String?
    private var lastRegistration: Date?
    private var pending: NativePushNotice?
    private var openAttempt = UUID()
    private var epoch = UUID()
    private var registrationTask: Task<Void, Never>?
    private var installationID: String {
        let key = "pubo.nativePushInstallationID"
        if let saved = UserDefaults.standard.string(forKey: key), UUID(uuidString: saved) != nil { return saved }
        let value = UUID().uuidString.lowercased(); UserDefaults.standard.set(value, forKey: key); return value
    }
    private func preference(_ owner: String) -> String { "pubo.nativePushEnabled." + owner }
    private func operation() -> [String: JSONValue] {
        let key = "pubo.nativePushOperationRevision"
        let previous = UserDefaults.standard.double(forKey: key)
        let revision = max(previous + 1, floor(Date().timeIntervalSince1970 * 1000))
        UserDefaults.standard.set(revision, forKey: key)
        return ["installationId": .string(installationID), "revision": .number(revision),
                "environment": .string(Bundle.main.object(forInfoDictionaryKey: "PUBOAPNSEnvironment") as? String ?? ""),
                "bundleId": .string(Bundle.main.bundleIdentifier ?? "")]
    }

    func resume() async {
        guard let session, let owner = session.user?.id else { return }
        let generation = epoch
        if let pending { self.pending = nil; await open(pending) }
        guard generation == epoch, session.user?.id == owner, !Task.isCancelled else { return }
        guard !session.testMode else { return }
        enabled = UserDefaults.standard.bool(forKey: preference(owner))
        guard session.meta["nativePushAvailable"].bool else { status = "本站锁屏推送通道尚未开放，App 内通知继续正常更新。"; return }
        guard enabled else { status = "未开启锁屏推送。"; return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard generation == epoch, session.user?.id == owner, !Task.isCancelled else { return }
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { status = "请在 iPhone 设置中允许 PUBO 通知。"; return }
        UIApplication.shared.registerForRemoteNotifications()
        if let deviceToken { await receivedToken(deviceToken) }
    }

    func enable() async {
        guard !busy, let session, !session.testMode, session.meta["nativePushAvailable"].bool, let owner = session.user?.id else { return }
        epoch = UUID(); registrationTask?.cancel(); registrationTask = nil
        let generation = epoch
        busy = true; defer { busy = false }
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            guard generation == epoch, session.user?.id == owner, !Task.isCancelled else { return }
            guard granted else { status = "尚未允许通知，可以在 iPhone 设置中修改。"; return }
            UserDefaults.standard.set(true, forKey: preference(owner)); enabled = true
            status = "正在注册设备…"; UIApplication.shared.registerForRemoteNotifications()
        } catch { status = "无法读取通知权限，请稍后重试。" }
    }

    func receivedToken(_ value: String) async {
        deviceToken = value
        guard let session, !session.testMode, enabled, session.meta["nativePushAvailable"].bool, let owner = session.user?.id else { return }
        let generation = epoch
        if registeredOwner == owner && registeredToken == session.token && registeredDeviceToken == value && lastRegistration.map({ Date().timeIntervalSince($0) < 86_400 }) == true { return }
        guard registrationTask == nil else { return }
        var fields = operation(); fields["deviceToken"] = .string(value)
        registrationTask = Task { @MainActor [weak self, weak session] in
            guard let self, let session else { return }
            defer { if generation == self.epoch { self.registrationTask = nil } }
            do {
                guard generation == self.epoch, owner == session.user?.id, self.enabled, !Task.isCancelled else { return }
                guard let environment = Bundle.main.object(forInfoDictionaryKey: "PUBOAPNSEnvironment") as? String, ["development", "production"].contains(environment) else { throw APIError.invalidResponse }
                let result = try await session.call("native-push/register", fields, mutation: true)
                guard generation == self.epoch, owner == session.user?.id, !Task.isCancelled else { return }
                guard result["subscriptionId"].string != nil else { throw APIError.uncertain }
                self.registeredOwner = owner; self.registeredToken = session.token; self.registeredDeviceToken = value; self.lastRegistration = Date(); self.status = "设备已登记。实际投递仍取决于系统通知设置和网络。"
            } catch { if generation == self.epoch { self.status = error.localizedDescription } }
        }
        await registrationTask?.value
        if generation == epoch, enabled, let latest = deviceToken, latest != value { await receivedToken(latest) }
    }

    func disable() async {
        guard let session, let owner = session.user?.id else { return }
        UserDefaults.standard.set(false, forKey: preference(owner)); enabled = false; epoch = UUID()
        let generation = epoch
        let fields = operation()
        registrationTask?.cancel(); registrationTask = nil
        registeredOwner = nil; registeredToken = nil; registeredDeviceToken = nil; lastRegistration = nil
        UIApplication.shared.unregisterForRemoteNotifications()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        do {
            _ = try await session.call("native-push/unregister", fields, mutation: true)
            guard generation == epoch, session.user?.id == owner else { return }
            status = "锁屏推送已关闭。"
        } catch { if generation == epoch, session.user?.id == owner { status = "本机已停止接收；服务器注销结果待确认，请联网后重试关闭。" } }
    }

    /// Clear local delivery immediately; a bounded best-effort request uses the old authorization only.
    func logout(preservePreference: Bool = false, preservePendingNotice: Bool = false) {
        let retainedNotice = preservePendingNotice ? pending : nil
        openAttempt = UUID()
        epoch = UUID(); let inFlight = registrationTask; registrationTask?.cancel(); registrationTask = nil
        if let session, !session.testMode {
            if !preservePreference, let owner = session.user?.id { UserDefaults.standard.removeObject(forKey: preference(owner)) }
            if let token = session.token {
                let api = session.api; let fields = operation()
                Task { await inFlight?.value; _ = try? await api.call("native-push/unregister", body: fields, token: token, mutation: true) }
            }
            UIApplication.shared.unregisterForRemoteNotifications()
            UNUserNotificationCenter.current().removeAllDeliveredNotifications()
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        }
        enabled = false; deviceToken = nil; registeredOwner = nil; registeredToken = nil; registeredDeviceToken = nil; lastRegistration = nil; pending = retainedNotice
    }

    func foregroundUpdate() { session?.streamRevision += 1 }
    func open(_ notice: NativePushNotice) async {
        guard let session else { pending = notice; return }
        if session.restoring { pending = notice; return }
        guard notice.belongs(to: session.user?.id) else { return }
        let generation = session.generation, attempt = UUID()
        openAttempt = attempt
        do {
            if notice.kind == .chat {
                let message = Record(try await session.call("chat/messages/show", ["messageId": .string(notice.eventID)]))
                guard openAttempt == attempt, generation == session.generation, message.id == notice.eventID, message["recalledAt"].isNull, message["toUserId"].string == session.user?.id else { return }
                let peerID = message["fromUserId"].string ?? ""
                let peer = Record(try await session.call("users/show", ["userId": .string(peerID)]))
                guard openAttempt == attempt, generation == session.generation, notice.belongs(to: session.user?.id), peer.id == peerID else { return }
                session.open(.chat(userID: peer.id), owner: notice.accountID, generation: generation)
            } else {
                let values = Record.list(try await session.call("i/notifications", ["limit": .number(100)]))
                guard openAttempt == attempt, generation == session.generation, notice.belongs(to: session.user?.id) else { return }
                guard let notification = values.first(where: { $0.id == notice.eventID }) else {
                    session.open(.notifications, owner: notice.accountID, generation: generation)
                    return
                }
                let route = AppNavigationPolicy.notificationRoute(notification.raw)
                if case .note(let noteID) = route {
                    let note = try await session.call("notes/show", ["noteId": .string(noteID)])
                    guard note["id"].string == noteID else { throw APIError.invalidResponse }
                }
                guard openAttempt == attempt else { return }
                session.open(route, owner: notice.accountID, generation: generation)
            }
        } catch { if openAttempt == attempt, generation == session.generation { status = "通知内容不可读取，请在 App 内重新核对账号与权限。" } }
    }
}

struct NativePushSettingsView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.openURL) private var openURL
    var body: some View {
        Form {
            Text(session.nativePush.status)
            Text("锁屏只显示通用提醒，不展示私信正文或附件。前台通过 App 内通知更新。").font(.footnote)
            if session.meta["nativePushAvailable"].bool {
                Button("开启锁屏推送") { Task { await session.nativePush.enable() } }.disabled(session.nativePush.busy)
            } else { Text("通道开放后，可在这里授权接收通知。").foregroundStyle(.secondary) }
            Button("关闭并注销本机推送") { Task { await session.nativePush.disable() } }
            Button("打开 iPhone 通知设置") { if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) } }
        }.puboForm().navigationTitle("锁屏推送").task { await session.nativePush.resume() }
    }
}
