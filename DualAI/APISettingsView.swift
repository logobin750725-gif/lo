import SwiftUI

struct APISettingsView: View {
    @ObservedObject var store: APIStore
    @Environment(\.dismiss) private var dismiss
    @State private var editing: APIProfile?
    @State private var removing: APIProfile?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("使用真實 API", isOn: $store.liveEnabled)
                    Text("關閉時使用明確標示的示範。開啟後，分析與測試會把文字送到你設定的服務並可能收費。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("系統 A 使用的模型") {
                    Picker("模型", selection: $store.selectedA) {
                        Text("尚未選擇").tag("")
                        ForEach(store.profiles) { p in Text(p.name + " · " + p.model).tag(p.id.uuidString) }
                    }
                }
                Section {
                    ForEach(store.profiles) { p in
                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                Text(p.name).font(.headline)
                                Spacer()
                                Button("編輯") { editing = p }.buttonStyle(.borderless)
                            }
                            Text(p.provider.title + " / " + p.model).font(.caption).foregroundStyle(.secondary)
                            Text(p.baseURL).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                            Toggle("參與系統 B", isOn: Binding(get: { p.useForB }, set: { store.setB($0, profile: p) })).font(.subheadline)
                            if let r = store.record(for: p) {
                                Label(r.success ? "最近連線測試成功" : "最近連線測試失敗", systemImage: r.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(r.success ? Color.green : Color.red).font(.subheadline)
                                Text(r.date.formatted(date: .abbreviated, time: .standard)).font(.caption2).foregroundStyle(.secondary)
                                if let status = r.status { Text("HTTP \(status)" + (r.latencyMS.map { " · \($0) ms" } ?? "")).font(.caption) }
                                if let model = r.reportedModel { Text("服務回報模型：" + model).font(.caption).textSelection(.enabled) }
                                if let text = r.response { Text("收到回覆：" + text).font(.caption).textSelection(.enabled) }
                                if r.inputTokens != nil || r.outputTokens != nil { Text("Tokens：輸入 \(r.inputTokens.map(String.init) ?? "未提供") / 輸出 \(r.outputTokens.map(String.init) ?? "未提供")").font(.caption2) }
                                if let error = r.error { Text(error).foregroundStyle(.red).font(.caption) }
                            } else {
                                Label(store.hasKey(p) ? "已設定 · 尚未測試" : "尚未設定 Key", systemImage: "circle.dashed").font(.subheadline).foregroundStyle(.orange)
                            }
                            HStack {
                                Button(store.testingID == p.id ? "測試中…" : "測試連線") { Task { await store.test(p) } }
                                    .disabled(store.testingID != nil).buttonStyle(.bordered)
                                Spacer()
                                Button("刪除", role: .destructive) { removing = p }.buttonStyle(.borderless)
                            }
                        }.padding(.vertical, 6)
                    }
                    Button { editing = APIProfile() } label: { Label("新增 API／模型", systemImage: "plus.circle") }
                } header: { Text("API 模組") } footer: {
                    Text("測試會實際呼叫模型並可能收費。成功只代表所示時間收到有效回覆，不能保證之後永遠連得上。B 使用勾選的 2–6 個不同端點／模型，總呼叫數為 2N+1。Key 保存在此裝置 Keychain，不會交給網頁或寫入匯出紀錄。")
                }
            }
            .navigationTitle("API 管理")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .sheet(item: $editing) { profile in APIProfileEditor(store: store, original: profile) }
            .confirmationDialog("刪除此設定與手機內的 Key？", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
                Button("刪除", role: .destructive) { if let p = removing { store.delete(p) }; removing = nil }
            }
        }
    }
}

struct APIProfileEditor: View {
    @ObservedObject var store: APIStore
    let original: APIProfile
    @State private var profile: APIProfile
    @State private var key = ""
    @State private var error = ""
    @Environment(\.dismiss) private var dismiss

    init(store: APIStore, original: APIProfile) {
        self.store = store
        self.original = original
        _profile = State(initialValue: original)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("服務") {
                    TextField("自訂名稱，例如：工作用模型", text: $profile.name)
                    Picker("API 格式", selection: $profile.provider) { ForEach(APIProvider.allCases) { Text($0.title).tag($0) } }
                    TextField("模型 ID（依服務帳號提供）", text: $profile.model).textInputAutocapitalization(.never).autocorrectionDisabled()
                    if profile.provider == .compatible {
                        TextField("https://你的服務/v1", text: $profile.customBaseURL).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        Text("填 Base URL，程式會接上 /chat/completions。不同服務的參數相容程度可能不同，請先測試。")
                            .font(.caption).foregroundStyle(.secondary)
                    } else { Text(profile.baseURL).font(.caption).foregroundStyle(.secondary) }
                }
                Section("API Key") {
                    SecureField(store.hasKey(original) ? "留空保留原 Key；輸入可替換" : "貼上 API Key", text: $key)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("只保存在這台 iPhone 的 Keychain。儲存後連線狀態會重設，需重新測試。自訂服務會收到你填入的 Key 與問題，請確認端點。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !error.isEmpty { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("API 設定")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("儲存") {
                    do {
                        profile.name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        profile.model = profile.model.trimmingCharacters(in: .whitespacesAndNewlines)
                        profile.customBaseURL = profile.customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        try store.save(profile, newKey: key)
                        key = ""
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                } }
            }
        }
    }
}
