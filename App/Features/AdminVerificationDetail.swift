import SwiftUI
import PUBOCore

struct AdminVerificationDetail: View {
    @Environment(AppSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    let applicationID: String
    @State private var application: JSONValue = .null
    @State private var error: String?
    @State private var busy = false
    @State private var generation = UUID()
    var body: some View {
        AdminGate {
            List {
                if let error { ErrorBanner(message: error); Button("重试") { Task { await load() } } }
                if busy { ProgressView() }
                if !application.isNull {
                    Section("申请资料") { AdminResultView(value: .object(application.object.filter { $0.key != "documents" })) }
                    Section("受保护材料") {
                        Text("仅管理员可读取，访问会记录在审核日志。材料只在当前页面内存中显示，不能导出或保存。").font(.footnote)
                        ForEach(Record.list(application["documents"])) { document in
                            NavigationLink(document["side"].string == "front" ? "查看正面" : "查看背面") { AdminVerificationDocument(applicationID: applicationID, document: document) }
                        }
                    }
                    Section("审核操作") {
                        ForEach(actions, id: \.self) { action in
                            if let endpoint = AdminCatalog.shared?.endpoint("admin/verification/" + action) { NavigationLink(AdminCatalog.title(endpoint.id)) { AdminOperationView(endpoint: endpoint, seed: application, source: "admin/verification/show") } }
                        }
                    }
                }
            }.puboForm().navigationTitle("认证申请").task { await load() }.refreshable { await load() }
                .onChange(of: scenePhase) { _, phase in if phase != .active { clear() } }
                .onChange(of: session.admin.unlocked) { _, unlocked in if !unlocked { clear() } }
        }
    }
    private var actions: [String] { application["status"].string == "pending" ? ["approve", "reject"] : (application["status"].string == "approved" ? ["revoke"] : []) }
    private func load() async {
        guard !busy else { return }; busy = true; defer { busy = false }; let request = generation
        do { let response = try await session.admin.call(session: session, path: "admin/verification/show", fields: ["applicationId": .string(applicationID)]); guard request == generation else { return }; application = response; error = nil }
        catch { if request == generation { application = .null; self.error = error.localizedDescription } }
    }
    private func clear() { generation = UUID(); application = .null; error = nil }
}

struct AdminVerificationDocument: View {
    @Environment(AppSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    let applicationID: String
    let document: Record
    @State private var image: UIImage?
    @State private var error: String?
    @State private var loading = false
    @State private var generation = UUID()
    @State private var captured = UIScreen.main.isCaptured
    var body: some View {
        AdminGate {
            ScrollView {
                VStack(spacing: 20) {
                    Text("受保护认证材料 · 禁止转发").font(.headline)
                    if scenePhase == .active && !captured, let image { Image(uiImage: image).resizable().scaledToFit().accessibilityLabel("认证材料预览") }
                    else if captured { Text("屏幕录制或共享期间不显示材料。") }
                    if loading { ProgressView() }
                    if let error { ErrorBanner(message: error) }
                    if image == nil && !captured { Button("读取材料（记录访问）") { Task { await load() } }.disabled(loading) }
                }.padding()
            }.navigationTitle("受保护材料")
                .onDisappear { clear() }
                .onChange(of: scenePhase) { _, phase in if phase != .active { clear() } }
                .onChange(of: session.admin.unlocked) { _, unlocked in if !unlocked { clear() } }
                .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { _ in captured = UIScreen.main.isCaptured; if captured { clear() } }
        }
    }
    private func load() async {
        guard !loading, !captured, scenePhase == .active else { return }; loading = true; defer { loading = false }; let request = generation
        do {
            let response = try await session.admin.call(session: session, path: "admin/verification/document", fields: ["applicationId": .string(applicationID), "documentId": .string(document.id)])
            guard request == generation, scenePhase == .active, !captured else { return }
            guard ["image/jpeg", "image/png", "image/webp"].contains(response["mime"].string ?? ""), let encoded = response["data"].string, encoded.utf8.count <= 14 * 1024 * 1024, let bytes = Data(base64Encoded: encoded), bytes.count <= 10 * 1024 * 1024, let decoded = UIImage(data: bytes) else { throw APIError.invalidResponse }
            image = decoded; error = nil
        } catch { if request == generation { clear(); self.error = error.localizedDescription } }
    }
    private func clear() { generation = UUID(); image = nil; error = nil }
}
