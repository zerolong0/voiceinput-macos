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
    case contentDriftDetected
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
        只改写用户输入，不做扩写。
        只允许纠错、语序优化、术语规范。
        禁止新增原文未提及的信息、步骤、方案、角色、验收、风险、里程碑。
        保留原始意图、约束、数字、专有名词。
        原文是分点就保持分点；原文是自然句就保持自然句。
        原文已清晰时仅做最小改动。
        不得反问用户，不得要求用户补充文本。
        不输出解释、标题、前后缀。
        禁止输出：改写后、优化后、根据你的、作为、我将、下面是。
        禁止输出符号：* # ` [ ]。
        仅输出最终改写文本。
        """

        switch style {
        case "vibe_coding", "technical":
            return """
            \(baseRules)
            Web Coding 术语规范：
            仅在不改变原意的前提下，纠正为 prompt、onboarding、frontend、backend、API。
            """
        case "formal", "email":
            return """
            \(baseRules)
            保持正式、礼貌、明确，但不得新增原文没有的承诺或计划。
            """
        case "casual", "chat":
            return """
            \(baseRules)
            保持口语化、自然、简洁，不夸张，不添加额外信息。
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

        if hasForbiddenFormatting(text: out) {
            throw PolishClientError.contentDriftDetected
        }

        if isLengthTooLong(original: original, output: out) {
            throw PolishClientError.contentDriftDetected
        }

        if isSemanticDrift(original: original, output: out) {
            throw PolishClientError.contentDriftDetected
        }

        if out.isEmpty {
            throw PolishClientError.decodeFailed
        }

        return out
    }

    private func isPromptLeak(text: String) -> Bool {
        let hitTerms = [
            "强约束", "结构规则", "场景补充", "仅允许重写", "不得扩写",
            "不自动补充", "任务：把用户输入改写", "system prompt",
            "你是文本改写器", "只输出改写后的正文"
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

    private func hasForbiddenFormatting(text: String) -> Bool {
        let forbiddenPrefixTerms = [
            "改写后", "优化后", "根据你的", "作为", "我将", "下面是",
            "请提供需要改写", "请提供要改写", "请提供需要优化", "请提供文本"
        ]
        if forbiddenPrefixTerms.contains(where: { text.hasPrefix($0) }) {
            return true
        }
        if text.contains("*") || text.contains("#") || text.contains("`") || text.contains("[") || text.contains("]") {
            return true
        }
        return false
    }

    private func isLengthTooLong(original: String, output: String) -> Bool {
        guard !original.isEmpty else { return false }
        let ratio = Double(output.count) / Double(original.count)
        if original.count <= 12 {
            return ratio > 1.8
        }
        return ratio > 1.35
    }

    private func isSemanticDrift(original: String, output: String) -> Bool {
        let sourceTokens = Set(extractSemanticTokens(from: original))
        guard sourceTokens.count >= 2 else { return false }

        let outputLower = output.lowercased()
        let overlap = sourceTokens.filter { token in
            outputLower.contains(token.lowercased())
        }.count
        let overlapRatio = Double(overlap) / Double(sourceTokens.count)
        return overlapRatio < 0.22
    }

    private func extractSemanticTokens(from text: String) -> [String] {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let patterns = [
            "[A-Za-z][A-Za-z0-9_\\-\\.]{1,}",
            "[\\u4e00-\\u9fff]{2,}"
        ]
        var tokens: [String] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let matches = regex.matches(in: text, range: range)
            for match in matches {
                guard let r = Range(match.range, in: text) else { continue }
                let token = String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                if token.count >= 2 {
                    tokens.append(token)
                }
            }
        }
        return Array(Set(tokens)).prefix(20).map { String($0) }
    }
}
