import Foundation

final class FixtureTransport: APIHTTPTransport {
    var status = 200
    var malformed = false
    var empty = false
    var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()
        requests.append(request)
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        let model = body["model"] as? String ?? "gemini-fixture"
        let messages = body["messages"] as? [[String: Any]] ?? []
        let geminiSystem = ((body["systemInstruction"] as? [String: Any])?["parts"] as? [[String: Any]])?.first?["text"] as? String
        let system = body["system"] as? String ?? messages.first?["content"] as? String ?? geminiSystem ?? ""
        let isJudge = system.contains("仲裁") || system.contains("綜合全部")
        let text = empty ? "" : "{\"answer\":\"\(isJudge ? "judge-result" : model + "-answer")\",\"evidence\":[\"fixture\"],\"issues\":[]}"
        let object: [String: Any]
        if request.url!.path.hasSuffix("/messages") {
            object = ["model": model, "content": [["type": "text", "text": text]], "usage": ["input_tokens": 7, "output_tokens": 8]]
        } else if request.url!.path.contains(":generateContent") {
            object = ["modelVersion": model, "candidates": [["content": ["parts": [["text": text]]]]], "usageMetadata": ["promptTokenCount": 7, "candidatesTokenCount": 8]]
        } else {
            object = ["model": model, "choices": [["message": ["content": text]]], "usage": ["prompt_tokens": 7, "completion_tokens": 8]]
        }
        let data = try (malformed ? Data("not json".utf8) : JSONSerialization.data(withJSONObject: object))
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

@main
struct AdapterTests {
    static func check(_ result: @autoclosure () -> Bool, _ description: String) {
        guard result() else { fatalError("FAIL: " + description) }
    }
    static func main() async throws {
        var count = 0
        for provider in APIProvider.allCases {
            var profile = APIProfile(name: "fixture", provider: provider, model: "account-model", customBaseURL: "https://custom.example/v1")
            let fixture = FixtureTransport()
            let adapter = APIAdapter(transport: fixture)
            let reply = try await adapter.chat(profile: profile, key: "offline-only-test-key", prompt: "test", system: "brief", test: true)
            check(reply.httpStatus == 200 && !reply.text.isEmpty, "valid reply is required for test success")
            check(reply.inputTokens == 7 && reply.outputTokens == 8, "provider usage mapping")
            let request = fixture.requests[0]
            check(!(request.url!.absoluteString.contains("offline-only-test-key")), "key never appears in URL")
            switch provider {
            case .groq, .openai, .compatible:
                check(request.url!.path.hasSuffix("/chat/completions"), "chat completions endpoint")
                check(request.value(forHTTPHeaderField: "Authorization") == "Bearer offline-only-test-key", "bearer header")
            case .claude:
                check(request.value(forHTTPHeaderField: "x-api-key") == "offline-only-test-key", "Claude key header")
                check(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01", "Claude version header")
            case .gemini:
                check(request.value(forHTTPHeaderField: "x-goog-api-key") == "offline-only-test-key", "Gemini key header")
                check(request.url!.path.hasSuffix("account-model:generateContent"), "Gemini endpoint")
            }
            for status in [401, 402, 404, 429, 503, 302] {
                fixture.status = status
                do {
                    _ = try await adapter.chat(profile: profile, key: "offline-only-test-key", prompt: "q", system: "s")
                    fatalError("HTTP errors must never be marked connected")
                } catch let error as APIError {
                    check(error.status == status, "HTTP error code preserved")
                    check(!error.message.contains("offline-only-test-key"), "no secret in error")
                }
            }
            fixture.status = 200
            fixture.empty = true
            do { _ = try await adapter.chat(profile: profile, key: "key", prompt: "q", system: "s"); fatalError("empty reply must fail") }
            catch let error as APIError { check(error.status == 200, "2xx empty reply is not a successful test") }
            fixture.empty = false
            fixture.malformed = true
            do { _ = try await adapter.chat(profile: profile, key: "key", prompt: "q", system: "s"); fatalError("HTML/non-JSON must fail") }
            catch let error as APIError { check(error.status == 200, "2xx non-JSON is not a successful test") }
            profile.provider = .compatible
            for base in ["http://custom.example/v1", "https://user:pass@custom.example/v1", "https://custom.example/v1?key=x"] {
                profile.customBaseURL = base
                do { _ = try APIAdapter.validate(profile); fatalError("invalid base must fail") }
                catch is APIError {}
            }
            count += 1
        }
        let p1 = APIProfile(name: "First", provider: .openai, model: "model-1")
        let p2 = APIProfile(name: "Second", provider: .compatible, model: "model-2", customBaseURL: "https://custom.example/v1")
        let transport = FixtureTransport()
        let pipeline = NativePipeline(adapter: APIAdapter(transport: transport))
        let report = try await pipeline.run(question: "offline fixture", system: "B", credentials: [(p1, "fixture-key-1"), (p2, "fixture-key-2")])
        check((report["final"] as! [String: Any])["answer"] as? String == "judge-result", "real judge step used")
        let stats = report["stats"] as! [String: Any]
        check(stats["calls"] as? Int == 5, "independent + critique + judge all counted")
        check(stats["inputTokens"] as? Int == 35 && stats["outputTokens"] as? Int == 40, "all usage included")
        check(stats["costUsd"] is NSNull, "no fabricated fee")
        let crossBody = try JSONSerialization.jsonObject(with: transport.requests[2].httpBody!) as! [String: Any]
        let crossMessages = crossBody["messages"] as! [[String: Any]]
        let promptData = (crossMessages.last!["content"] as! String).data(using: .utf8)!
        let prompt = try JSONSerialization.jsonObject(with: promptData) as! [String: Any]
        let peers = prompt["context"] as! [[String: Any]]
        check(peers.count == 1, "cross review excludes own answer")
        check((peers[0]["answer"] as! [String: Any])["answer"] as? String == "model-2-answer", "only peer answer provided")
        let encoded = String(decoding: try JSONSerialization.data(withJSONObject: report), as: UTF8.self)
        check(!encoded.contains("fixture-key"), "report does not contain Key")
        do { _ = try await pipeline.run(question: "q", system: "B", credentials: [(p1, "key"), (p1, "key")]); fatalError("duplicates must fail") }
        catch is APIError {}
        do { _ = try StructuredAnswer.parse("{\"answer\":\"x\",\"evidence\":\"bad\",\"issues\":[]}"); fatalError("bad structure must fail") }
        catch is APIError {}
        let a = try await pipeline.run(question: "q", system: "A", credentials: [(p1, "key")])
        check((a["stats"] as! [String: Any])["calls"] as? Int == 5, "A runs all five stages")
        let judge = APIProfile(name: "Gemini judge", provider: .gemini, model: "gemini-3.8-flash", useForB: false, freePlanConfirmed: true)
        let judged = try await pipeline.run(question: "q", system: "B", credentials: [(p1, "key"), (p2, "key")], judge: (judge, "judge-secret"))
        check(transport.requests.last!.url!.path.hasSuffix("gemini-3.8-flash:generateContent"), "final call uses separate Gemini endpoint")
        check(transport.requests.last!.value(forHTTPHeaderField: "x-goog-api-key") == "judge-secret", "judge uses its own key")
        check((judged["stats"] as! [String: Any])["models"] as? Int == 3, "independent judge included in model count")
        check((judged["final"] as! [String: Any])["answer"] as? String == "judge-result", "Gemini judge result returned")
        let before = transport.requests.count
        do { _ = try await pipeline.run(question: "q", system: "A", credentials: [(p1, "key")], judge: (p1, "key")); fatalError("shared judge must fail") }
        catch is APIError { check(transport.requests.count == before, "shared judge rejected before HTTP") }
        try FreeTrialPolicy.validate(judge)
        var unconfirmed = judge
        unconfirmed.freePlanConfirmed = nil
        do { try FreeTrialPolicy.validate(unconfirmed); fatalError("free plan confirmation required") } catch is APIError {}
        let llama = APIProfile(name: "Llama", provider: .groq, model: "llama-3.3-70b-versatile", freePlanConfirmed: true)
        do { try FreeTrialPolicy.validate(llama); fatalError("enterprise Llama is not a free preset") } catch is APIError {}
        print("PASS: \(count) adapters, actual HTTP request/reply fixtures, error and empty-response rejection, endpoint validation, peer exclusion, judge, complete usage, duplicate rejection and secret-free reports. No real API calls.")
    }
}
