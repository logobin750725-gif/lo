import Foundation

enum APIProvider: String, Codable, CaseIterable, Identifiable {
    case openai, claude, gemini, compatible
    var id: String { rawValue }
    var title: String {
        switch self {
        case .openai: return "OpenAI"
        case .claude: return "Claude"
        case .gemini: return "Gemini"
        case .compatible: return "OpenAI 相容／自訂"
        }
    }
    var baseURL: String {
        switch self {
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
