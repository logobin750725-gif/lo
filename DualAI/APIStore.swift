import Foundation
import SwiftUI
import Security

enum APIKeychain {
    private static let service = "org.dualai.mobilelab.api-keys"
    private static func query(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: id.uuidString]
    }
    static func read(_ id: UUID) -> String? {
        var q = query(id)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func write(_ key: String, id: UUID) throws {
        let data = Data(key.utf8)
        let status = SecItemUpdate(query(id) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw APIError(message: "無法更新 Keychain，設定沒有儲存。") }
        var q = query(id)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw APIError(message: "無法寫入 Keychain，設定沒有儲存。") }
    }
    static func delete(_ id: UUID) { SecItemDelete(query(id) as CFDictionary) }
}

@MainActor
final class APIStore: ObservableObject {
    @Published private(set) var profiles: [APIProfile] = []
    @Published private(set) var records: [String: ConnectionRecord] = [:]
    @Published var liveEnabled = false { didSet { persist() } }
    @Published var selectedA: String = "" { didSet { persist() } }
    @Published var selectedJudge: String = "" { didSet { persist() } }
    @Published var testingID: UUID?
    var onChange: (() -> Void)?
    private let defaults = UserDefaults.standard

    init() {
        if let data = defaults.data(forKey: "api.profiles.v2"), let value = try? JSONDecoder().decode([APIProfile].self, from: data) { profiles = value }
        if let data = defaults.data(forKey: "api.tests.v2"), let value = try? JSONDecoder().decode([String: ConnectionRecord].self, from: data) { records = value }
        selectedJudge = defaults.string(forKey: "api.selectedJudge.v3") ?? ""
        selectedA = defaults.string(forKey: "api.selectedA.v2") ?? ""
        liveEnabled = defaults.bool(forKey: "api.liveEnabled.v2")
    }
    func persist() {
        if let data = try? JSONEncoder().encode(profiles) { defaults.set(data, forKey: "api.profiles.v2") }
        if let data = try? JSONEncoder().encode(records) { defaults.set(data, forKey: "api.tests.v2") }
        defaults.set(liveEnabled, forKey: "api.liveEnabled.v2")
        defaults.set(selectedJudge, forKey: "api.selectedJudge.v3")
        defaults.set(selectedA, forKey: "api.selectedA.v2")
        onChange?()
    }
    func save(_ profile: APIProfile, newKey: String) throws {
        _ = try APIAdapter.validate(profile)
        let key = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !profiles.contains(where: { $0.id == profile.id }) && profiles.count >= 12 { throw APIError(message: "最多保留 12 個 API 設定。") }
        if let old = profiles.first(where: { $0.id == profile.id }), old.baseURL != profile.baseURL, key.isEmpty {
            throw APIError(message: "服務端點已變更，請重新填入此服務的 Key，避免把舊 Key 傳到其他服務。")
        }
        if key.isEmpty && APIKeychain.read(profile.id) == nil { throw APIError(message: "新增設定需要 API Key。") }
        if !key.isEmpty { try APIKeychain.write(key, id: profile.id) }
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) { profiles[index] = profile }
        else {
            guard profiles.count < 12 else { throw APIError(message: "最多保留 12 個 API 設定。") }
            profiles.append(profile)
        }
        records.removeValue(forKey: profile.id.uuidString)
        if selectedA.isEmpty { selectedA = profile.id.uuidString }
        if selectedJudge.isEmpty && profile.provider == .gemini { selectedJudge = profile.id.uuidString }
        persist()
    }
    func delete(_ profile: APIProfile) {
        if selectedJudge == profile.id.uuidString { selectedJudge = "" }
        APIKeychain.delete(profile.id)
        profiles.removeAll { $0.id == profile.id }
        records.removeValue(forKey: profile.id.uuidString)
        if selectedA == profile.id.uuidString { selectedA = profiles.first?.id.uuidString ?? "" }
        persist()
    }
    func setB(_ value: Bool, profile: APIProfile) {
        if let i = profiles.firstIndex(where: { $0.id == profile.id }) { profiles[i].useForB = value; persist() }
    }
    func record(for profile: APIProfile) -> ConnectionRecord? { records[profile.id.uuidString] }
    func hasKey(_ profile: APIProfile) -> Bool { APIKeychain.read(profile.id) != nil }
    func test(_ profile: APIProfile) async {
        guard testingID == nil else { return }
        testingID = profile.id
        let start = Date()
        defer { testingID = nil }
        do {
            try FreeTrialPolicy.validate(profile)
            guard let key = APIKeychain.read(profile.id) else { throw APIError(message: "Keychain 內沒有此 API Key。") }
            let reply = try await APIAdapter().chat(profile: profile, key: key, prompt: "Reply with OK.", system: "This is a connection test. Reply briefly.", test: true)
            records[profile.id.uuidString] = ConnectionRecord(success: true, date: Date(), status: reply.httpStatus, latencyMS: reply.latencyMS,
                reportedModel: reply.model, response: String(reply.text.prefix(300)), inputTokens: reply.inputTokens, outputTokens: reply.outputTokens)
        } catch {
            records[profile.id.uuidString] = ConnectionRecord(success: false, date: Date(), status: (error as? APIError)?.status, latencyMS: Int(Date().timeIntervalSince(start) * 1000),
                error: (error as? APIError)?.message ?? "連線測試失敗，請檢查網路。")
        }
        persist()
    }
    func status() -> [String: Any] {
        ["enabled": liveEnabled, "selectedA": selectedA, "judgeReady": (try? judge()) != nil,
         "judgeModel": profiles.first { $0.id.uuidString == selectedJudge }?.model ?? "未設定",
         "models": profiles.map { p -> [String: Any] in
             let record = self.record(for: p)
             return ["id": p.id.uuidString, "name": p.name, "provider": p.provider.title, "model": p.model,
                     "useForB": p.useForB, "hasKey": hasKey(p), "tested": record?.success == true,
                     "lastTest": record.map { ISO8601DateFormatter().string(from: $0.date) } ?? ""]
         }]
    }
    func judge() throws -> (APIProfile, String) {
        guard let p = profiles.first(where: { $0.id.uuidString == selectedJudge }), p.provider == .gemini else { throw APIError(message: "請在 API 管理選擇 Gemini 獨立判官。") }
        try FreeTrialPolicy.validate(p)
        guard record(for: p)?.success == true, let key = APIKeychain.read(p.id) else { throw APIError(message: "請先測試 Gemini 判官連線。") }
        return (p, key)
    }
    func chosen(system: String) throws -> [(APIProfile, String)] {
        guard liveEnabled else { throw APIError(message: "尚未啟用真實 API 模式。") }
        let picked = system == "A" ? profiles.filter { $0.id.uuidString == selectedA } : profiles.filter(\.useForB)
        guard system == "A" ? picked.count == 1 : (2...6).contains(picked.count) else { throw APIError(message: "A 請選一個模型；B 請選 2 至 6 個模型。") }
        let referee = try judge()
        guard !picked.contains(where: { $0.identity == referee.0.identity }) else { throw APIError(message: "判官必須使用不同於回答者的模型。請取消 Gemini 判官的「參與系統 B」，A 請選 Groq。") }
        guard Set(picked.map(\.identity)).count == picked.count else { throw APIError(message: "同一端點與模型不能重複計為獨立模型。") }
        return try picked.map { p in
            try FreeTrialPolicy.validate(p)
            guard let key = APIKeychain.read(p.id) else { throw APIError(message: "\(p.name) 尚未設定 Key。") }
            guard record(for: p)?.success == true else { throw APIError(message: "請先對 \(p.name) 執行並通過連線測試。") }
            return (p, key)
        }
    }
}
