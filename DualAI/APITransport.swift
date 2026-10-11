import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

protocol APIHTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

struct LiveAPITransport: APIHTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 90
        config.httpShouldSetCookies = false
        let session = URLSession(configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError(message: "API 未回傳 HTTP 回應。") }
        return (data, http)
    }
}

struct APIAdapter {
    var transport: any APIHTTPTransport = LiveAPITransport()

    static func validate(_ profile: APIProfile) throws -> URL {
        guard !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !profile.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let components = URLComponents(string: profile.baseURL),
              components.scheme?.lowercased() == "https", components.host != nil,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              let url = components.url else {
            throw APIError(message: "請填名稱、模型 ID，以及不含帳密、query 或 fragment 的 HTTPS Base URL。")
        }
        return url
    }

    func request(profile: APIProfile, key: String, prompt: String, system: String, test: Bool = false) throws -> URLRequest {
        let base = try Self.validate(profile)
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw APIError(message: "尚未填入 API Key。") }
        let limit = test ? 256 : 2048
        var url: URL
        var payload: [String: Any]
        switch profile.provider {
        case .groq, .openai, .compatible:
            url = base.appendingPathComponent("chat/completions")
            payload = ["model": profile.model, "messages": [["role": "system", "content": system], ["role": "user", "content": prompt]]]
            if profile.provider == .openai || profile.provider == .groq { payload["max_completion_tokens"] = limit }
            else { payload["max_tokens"] = limit }
        case .claude:
            url = base.appendingPathComponent("messages")
            payload = ["model": profile.model, "system": system, "max_tokens": limit, "messages": [["role": "user", "content": prompt]]]
        case .gemini:
            let model = profile.model.hasPrefix("models/") ? String(profile.model.dropFirst(7)) : profile.model
            guard !model.contains("/"), !model.contains("?"), !model.contains("#") else { throw APIError(message: "Gemini 模型 ID 格式不正確。") }
            url = base.appendingPathComponent("models").appendingPathComponent(model + ":generateContent")
            payload = ["systemInstruction": ["parts": [["text": system]]], "contents": [["role": "user", "parts": [["text": prompt]]]], "generationConfig": ["maxOutputTokens": limit]]
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        switch profile.provider {
        case .groq, .openai, .compatible: request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        case .claude:
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .gemini: request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return request
    }

    func chat(profile: APIProfile, key: String, prompt: String, system: String, test: Bool = false) async throws -> APIReply {
        let req = try request(profile: profile, key: key, prompt: prompt, system: system, test: test)
        let start = Date()
        let data: Data
        let response: HTTPURLResponse
        do { (data, response) = try await transport.send(req) }
        catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch { throw APIError(message: "無法連線或請求逾時；請檢查網路與 API 端點。") }
        let ms = Int(Date().timeIntervalSince(start) * 1000)
        guard (200...299).contains(response.statusCode) else {
            let reason: String
            switch response.statusCode {
            case 401, 403: reason = "Key 無效、無權限，或服務拒絕存取。"
            case 402: reason = "餘額不足或預算已用完；已停止，沒有改用其他模型。"
            case 404: reason = "模型或 API 路徑不存在。"
            case 429: reason = "額度不足或請求太頻繁。"
            case 300...399: reason = "服務要求重新導向；為避免將 Key 轉送其他端點，已停止。"
            case 500...599: reason = "供應商服務暫時異常。"
            default: reason = "供應商拒絕此請求；請檢查模型與 API 格式。"
            }
            throw APIError(message: "HTTP \(response.statusCode)：\(reason)", status: response.statusCode)
        }
        guard data.count <= 8_000_000,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError(message: "HTTP 成功，但回覆不是有效 API JSON。", status: response.statusCode)
        }
        return try parse(object: object, profile: profile, status: response.statusCode, latencyMS: ms)
    }

    func parse(object: [String: Any], profile: APIProfile, status: Int, latencyMS: Int) throws -> APIReply {
        var text = ""
        var usage: [String: Any] = [:]
        var input: Int?
        var output: Int?
        var model = object["model"] as? String ?? "服務未回報（設定為 \(profile.model)）"
        switch profile.provider {
        case .groq, .openai, .compatible:
            if let choices = object["choices"] as? [[String: Any]], let message = choices.first?["message"] as? [String: Any] {
                text = message["content"] as? String ?? ""
            }
            usage = object["usage"] as? [String: Any] ?? [:]
            input = usage["prompt_tokens"] as? Int
            output = usage["completion_tokens"] as? Int
        case .claude:
            let parts = object["content"] as? [[String: Any]] ?? []
            text = parts.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined(separator: "\n")
            usage = object["usage"] as? [String: Any] ?? [:]
            input = usage["input_tokens"] as? Int
            output = usage["output_tokens"] as? Int
        case .gemini:
            let candidates = object["candidates"] as? [[String: Any]] ?? []
            let content = candidates.first?["content"] as? [String: Any] ?? [:]
            text = (content["parts"] as? [[String: Any]] ?? []).filter { $0["thought"] as? Bool != true }.compactMap { $0["text"] as? String }.joined(separator: "\n")
            usage = object["usageMetadata"] as? [String: Any] ?? [:]
            input = usage["promptTokenCount"] as? Int
            output = usage["candidatesTokenCount"] as? Int
            model = object["modelVersion"] as? String ?? "服務未回報（設定為 \(profile.model)）"
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw APIError(message: "HTTP 成功，但沒有可用的模型文字回覆；不標示連線成功。", status: status)
        }
        return APIReply(text: text, model: model, inputTokens: input, outputTokens: output, httpStatus: status, latencyMS: latencyMS)
    }
}
