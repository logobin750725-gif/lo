import Foundation

enum APIProvider: String, Codable, CaseIterable, Identifiable {
    case groq, openai, claude, gemini, compatible
    var id: String { rawValue }
    var title: String {
        switch self {
        case .groq: return "Groq"
        case .openai: return "OpenAI"
        case .claude: return "Claude"
        case .gemini: return "Gemini"
        case .compatible: return "OpenAI 相容／自訂"
        }
    }
    var baseURL: String {
        switch self {
        case .groq: return "https://api.groq.com/openai/v1"
        case .openai: return "https://api.openai.com/v1"
        case .claude: return "https://api.anthropic.com/v1"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta"
        case .compatible: return ""
        }
    }
}

struct APIProfile: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = ""
    var provider: APIProvider = .openai
    var model = ""
    var customBaseURL = ""
    var useForB = true
    var freePlanConfirmed: Bool? = nil
    var baseURL: String { provider == .compatible ? customBaseURL : provider.baseURL }
    var identity: String { baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased() + "|" + model }
}

struct ConnectionRecord: Codable {
    var success: Bool
    var date: Date
    var status: Int?
    var latencyMS: Int?
    var reportedModel: String?
    var response: String?
    var inputTokens: Int?
    var outputTokens: Int?
    var error: String?
}

struct APIReply {
    var text: String
    var model: String
    var inputTokens: Int?
    var outputTokens: Int?
    var httpStatus: Int
    var latencyMS: Int
}

struct APIError: LocalizedError {
    var message: String
    var status: Int? = nil
    var errorDescription: String? { message }
}

struct StructuredAnswer: Codable {
    var answer: String
    var evidence: [String]
    var issues: [String]

    static func parse(_ text: String) throws -> Self {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("```") {
            let lines = value.components(separatedBy: .newlines)
            if lines.count >= 3, lines.last?.hasPrefix("```") == true {
                value = lines.dropFirst().dropLast().joined(separator: "\n")
            }
        }
        guard let data = value.data(using: .utf8),
              let result = try? JSONDecoder().decode(Self.self, from: data),
              !result.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw APIError(message: "收到 API 回覆，但角色 JSON 格式不正確；沒有以示範結果替代。")
        }
        return result
    }
}

enum FreeTrialPolicy {
    static let groqModels = ["openai/gpt-oss-20b", "openai/gpt-oss-120b"]
    static let geminiModels = ["gemini-3.8-flash", "gemini-3.6-flash"]
    static func validate(_ profile: APIProfile) throws {
        let allowed = profile.provider == .groq ? groqModels : profile.provider == .gemini ? geminiModels : []
        guard allowed.contains(profile.model) else { throw APIError(message: "試玩版只允許清單內的 Groq／Gemini 模型；不會自動切換付費模型。Llama 的免費 API 尚未確認。") }
        guard profile.freePlanConfirmed == true else { throw APIError(message: "請先確認此 Key 的帳號／專案使用免費方案，且未開啟付費。App 無法讀取供應商帳單。") }
    }
}
