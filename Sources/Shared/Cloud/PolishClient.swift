import Foundation

struct PolishRequest: Encodable {
    let text: String
    let style: String
    let model: String
}

struct PolishResponse: Decodable {
    let original: String
    let polished: String
    let style: String
    let model: String
}

private struct OpenAIChatCompletionRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double
    let max_tokens: Int
}

private struct OpenAIChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }
        let message: Message
    }

    let choices: [Choice]
}

enum PolishClientError: Error {
    case invalidURL
    case missingAPIKey
    case badStatus(Int)
    case decodeFailed
    case promptLeakDetected
}

final class PolishClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func polish(text: String, style: String, model: String, baseURL: String, apiKey: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }
        guard apiKey.count >= 10 else { throw PolishClientError.missingAPIKey }

        if isOpenAICompat(baseURL: baseURL) {
            return try await polishViaOpenAICompat(text: trimmed, style: style, model: model, baseURL: baseURL, apiKey: apiKey)
        }
        return try await polishViaCloudAPI(text: trimmed, style: style, model: model, baseURL: baseURL, apiKey: apiKey)
    }

    private func polishViaCloudAPI(text: String, style: String, model: String, baseURL: String, apiKey: String) async throws -> String {
        let endpoint = baseURL.hasSuffix("/") ? "\(baseURL)polish/" : "\(baseURL)/polish/"
        guard let url = URL(string: endpoint) else {
            throw PolishClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            PolishRequest(text: text, style: style, model: model)
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PolishClientError.badStatus(-1)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw PolishClientError.badStatus(http.statusCode)
        }

        guard let decoded = try? JSONDecoder().decode(PolishResponse.self, from: data) else {
            throw PolishClientError.decodeFailed
        }
        return try sanitizeModelOutput(decoded.polished, original: text)
    }

    private func polishViaOpenAICompat(text: String, style: String, model: String, baseURL: String, apiKey: String) async throws -> String {
        let normalized = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        let endpoint = normalized.hasSuffix("/chat/completions") ? normalized : "\(normalized)/chat/completions"
        guard let url = URL(string: endpoint) else {
            throw PolishClientError.invalidURL
        }

        let req = OpenAIChatCompletionRequest(
            model: model,
            messages: [
                .init(role: "system", content: systemPrompt(for: style)),
                .init(role: "user", content: text)
            ],
            temperature: 0.1,
            max_tokens: 512
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(req)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PolishClientError.badStatus(-1)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw PolishClientError.badStatus(http.statusCode)
        }

        guard
            let decoded = try? JSONDecoder().decode(OpenAIChatCompletionResponse.self, from: data),
            let content = decoded.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
            !content.isEmpty
        else {
            throw PolishClientError.decodeFailed
        }
        return try sanitizeModelOutput(content, original: text)
    }

    private func isOpenAICompat(baseURL: String) -> Bool {
        baseURL.contains("open.bigmodel.cn") || baseURL.contains("oneapi.gemiaude.com") || baseURL.contains("/v1") || baseURL.contains("/v4") || baseURL.contains("/chat/completions")
    }

    private func systemPrompt(for style: String) -> String {
        let baseRules = """
        任务：把用户输入改写为更清晰、可执行的文本。

        强约束：
        1. 只允许重写、纠错、重排。禁止新增用户未提及的信息。
        2. 禁止添加角色设定、身份描述、背景故事、解释性前后缀。
        3. 禁止脑补功能、步骤、验收标准、风险项；除非原文已明确提到。
        4. 保留原始意图、约束、数字、专有名词。
        5. 修正常见错别字和不规范术语，不改变业务含义。
        6. 仅输出最终改写结果，不输出任何说明。
        7. 不使用星号、井号、反引号、方括号等特殊结构化符号。
        8. 不得扩写成新的需求清单、功能拆解或实施方案；除非原文已经给出这些结构。
        9. 输出长度默认不超过原文约 1.25 倍；若原文很短，只做必要纠错与术语规范。
        10. 若原文已清晰，优先最小改动；可直接返回轻微纠错后的原句。

        结构规则：
        1. 如果原文是列表/分点，保持分点并优化语序。
        2. 如果原文是自然句子，输出为简洁段落，不强行套模板。
        """

        switch style {
        case "vibe_coding", "technical":
            return """
            \(baseRules)
            场景补充：
            1. 偏向 Web Coding 语境做术语校正，例如 prompt、onboarding、frontend、backend、API。
            2. 不新增任何未给出的技术方案。
            3. 不自动补充“角色设定”“验收标准”“风险评估”“里程碑”等模板化段落。
            """
        case "formal", "email":
            return """
            \(baseRules)
            场景补充：
            语气正式、礼貌、明确，但不新增原文没有的承诺或计划。
            """
        case "casual", "chat":
            return """
            \(baseRules)
            场景补充：
            口语化、自然、简洁，不夸张，不添加额外信息。
            """
        default:
            return """
            \(baseRules)
            """
        }
    }

    private func sanitizeModelOutput(_ content: String, original: String) throws -> String {
        var out = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if out.hasPrefix("```") {
            out = out.replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if isPromptLeak(text: out) {
            throw PolishClientError.promptLeakDetected
        }

        if out.isEmpty {
            throw PolishClientError.decodeFailed
        }

        return out
    }

    private func isPromptLeak(text: String) -> Bool {
        let hitTerms = [
            "强约束", "结构规则", "场景补充", "仅允许重写", "不得扩写",
            "不自动补充", "任务：把用户输入改写", "你是", "system prompt"
        ]
        let hitCount = hitTerms.reduce(0) { partial, term in
            partial + (text.localizedCaseInsensitiveContains(term) ? 1 : 0)
        }
        if hitCount >= 2 { return true }

        // Obvious prompt template leakage
        if text.contains("1.") && text.contains("2.") && text.contains("3.") && text.contains("强约束") {
            return true
        }
        return false
    }
}
