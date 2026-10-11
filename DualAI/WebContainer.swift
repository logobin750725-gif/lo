import SwiftUI
import UIKit
import WebKit

struct WebContainer: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> LabViewController { LabViewController() }
    func updateUIViewController(_ uiViewController: LabViewController, context: Context) {}
}

final class LabViewController: UIViewController, WKScriptMessageHandler, WKUIDelegate, WKNavigationDelegate {
    private var webView: WKWebView!
    private var webRoot: URL?
    private var latestExport: URL?
    private let apiStore = APIStore()
    private var analysisTask: Task<Void, Never>?
    private var analysisID: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 246/255, green: 246/255, blue: 239/255, alpha: 1)
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(self, name: "exportJSON")
        configuration.userContentController.add(self, name: "apiBridge")
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.uiDelegate = self
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = view.backgroundColor
        webView.scrollView.backgroundColor = view.backgroundColor
        webView.translatesAutoresizingMaskIntoConstraints = false
        apiStore.onChange = { [weak self] in
            self?.webView.evaluateJavaScript("window.dispatchEvent(new Event('dualai-status'));", completionHandler: nil)
        }
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        guard let file = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Web") else {
            showError("App 缺少內建網頁資源，請重新建置。")
            return
        }
        webRoot = file.deletingLastPathComponent().standardizedFileURL
        webView.loadFileURL(file, allowingReadAccessTo: file.deletingLastPathComponent())
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || navigationController?.isBeingDismissed == true {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "exportJSON")
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "apiBridge")
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              let page = message.frameInfo.request.url, page.isFileURL,
              page.standardizedFileURL.deletingLastPathComponent() == webRoot else { return }
        if message.name == "apiBridge" {
            handleAPIMessage(message.body)
            return
        }
        guard message.name == "exportJSON",
              let json = message.body as? String,
              let data = json.data(using: .utf8), data.count <= 2_000_000 else { return }
        do {
            _ = try JSONSerialization.jsonObject(with: data)
            if let oldFile = latestExport { try? FileManager.default.removeItem(at: oldFile) }
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("DualAI-\(UUID().uuidString).json")
            try data.write(to: file, options: .atomic)
            latestExport = file
            let share = UIActivityViewController(activityItems: [file], applicationActivities: nil)
            share.popoverPresentationController?.sourceView = view
            share.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            present(share, animated: true)
        } catch {
            showError("無法匯出紀錄，請稍後再試。")
        }
    }

    private func reply(_ id: String, data: [String: Any]? = nil, error: String? = nil) {
        var envelope: [String: Any] = ["ok": error == nil]
        if let data = data { envelope["data"] = data }
        if let error = error { envelope["error"] = error }
        guard let bytes = try? JSONSerialization.data(withJSONObject: envelope) else { return }
        let encoded = bytes.base64EncodedString()
        webView.evaluateJavaScript("window.DualAIHost?.resolve('\(id)', '\(encoded)');", completionHandler: nil)
    }

    private func handleAPIMessage(_ body: Any) {
        guard let object = body as? [String: Any], let id = object["id"] as? String,
              id.range(of: "^[A-Za-z0-9-]{1,80}$", options: .regularExpression) != nil,
              let action = object["action"] as? String else { return }
        switch action {
        case "copyReview":
            guard let payload = object["payload"] as? [String: Any], let text = payload["text"] as? String,
                  text.utf8.count <= 500_000 else { reply(id, error: "審查資料太長。"); return }
            UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: text]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(600)])
            reply(id, data: ["copied": true])
        case "status": reply(id, data: apiStore.status())
        case "settings":
            guard analysisTask == nil else { reply(id, error: "分析中，請先停止再修改 API。"); return }
            let settings = UIHostingController(rootView: APISettingsView(store: apiStore))
            present(settings, animated: true)
            reply(id, data: ["opened": true])
        case "cancel":
            if analysisID == id { analysisTask?.cancel() }
        case "analyze":
            guard analysisTask == nil else { reply(id, error: "已有 API 分析進行中。"); return }
            guard let payload = object["payload"] as? [String: Any], let question = payload["question"] as? String,
                  let system = payload["system"] as? String, ["A", "B"].contains(system), question.count <= 2000 else {
                reply(id, error: "分析輸入不正確。"); return
            }
            do {
                let credentials = try apiStore.chosen(system: system)
                let judge = try apiStore.judge()
                analysisID = id
                analysisTask = Task { [weak self] in
                    guard let self = self else { return }
                    defer { self.analysisTask = nil; self.analysisID = nil }
                    do {
                        let report = try await NativePipeline().run(question: question, system: system, credentials: credentials, judge: judge)
                        self.reply(id, data: report)
                    } catch is CancellationError {
                        self.reply(id, error: "已停止分析；供應商已接收的請求仍可能計費。")
                    } catch {
                        self.reply(id, error: (error as? APIError)?.message ?? "API 分析失敗。")
                    }
                }
            } catch { reply(id, error: error.localizedDescription) }
        default: reply(id, error: "未知的 API 操作。")
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if url.isFileURL, let root = webRoot,
           url.standardizedFileURL.path.hasPrefix(root.path + "/") {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
            if navigationAction.navigationType == .linkActivated,
               ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                UIApplication.shared.open(url)
            }
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: "DualAI", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "清除", style: .destructive) { _ in completionHandler(true) })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showError("無法載入內建介面，請重新開啟 App。")
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "DualAI", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        DispatchQueue.main.async { [weak self] in self?.present(alert, animated: true) }
    }
}
