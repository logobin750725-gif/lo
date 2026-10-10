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

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 246/255, green: 246/255, blue: 239/255, alpha: 1)
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(self, name: "exportJSON")
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.uiDelegate = self
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = view.backgroundColor
        webView.scrollView.backgroundColor = view.backgroundColor
        webView.translatesAutoresizingMaskIntoConstraints = false
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
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "exportJSON", message.frameInfo.isMainFrame,
              let page = message.frameInfo.request.url, page.isFileURL,
              page.standardizedFileURL.deletingLastPathComponent() == webRoot,
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
