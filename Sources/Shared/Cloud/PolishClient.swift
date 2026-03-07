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
        request.timeoutInterval = effectiveTimeout(for: text)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            PolishRequest(text: text, style: style, model: model)
        )

        let (data, response) = try await performRequestWithRetry(request, retryCount: configuredRetryCount())
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
            temperature: 0.0,
            max_tokens: effectiveMaxTokens(for: text)
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = effectiveTimeout(for: text)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(req)

        let (data, response) = try await performRequestWithRetry(request, retryCount: configuredRetryCount())
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

    static func defaultSystemPrompt(for style: String) -> String {
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
        输出长度原则上不超过原文的 1.25 倍；短句仅做必要纠错。
        若无法确定是否需要改动，优先保留原句。
        仅输出最终改写文本。
        """

        switch style {
        case "vibe_coding", "technical":
            return """
            \(baseRules)
            Vibe Coding 术语规范：
            你面向的是开发者对 AI 编程助手发出的指令场景。
            目标是把口语输入整理为可执行的开发指令，不新增需求。
            输出结构要求（强调层次与可执行性）：
            当原文信息较复杂（包含多个动作、约束、上下文）时，按“需求目标 / 现状与上下文 / 具体修改 / 约束与边界”分段表达。
            每段使用简短标题行（如“需求目标：”），并换行给出内容；无对应信息则省略该段，不得脑补。
            若原文本身是分点，保持 1. 2. 3. 编号并优化语序；若原文是自然段，改为清晰短段落。
            句式尽量短，避免长句堆叠，确保一眼可执行。
            保留代码相关术语原样（函数名、变量名、文件名、CLI 命令）。
            中文口语技术词修正：
              接口→API，前端→frontend，后端→backend，数据库→database，部署→deploy，
              提示词→prompt，引导流程→onboarding，组件→component，钩子→hook，
              容器→container，镜像→image，流水线→pipeline，分支→branch，
              合并→merge，回滚→rollback，缓存→cache，路由→router。
            Vibe Coding 高频术语优先：
              页面→page，样式→CSS，状态管理→state management，接口联调→API integration，
              构建→build，发布→release，测试用例→test case，回归测试→regression test。
            保留数字、路径、版本号、包名不做修改。
            如果原文是给 AI 的指令（如"帮我写一个..."），保持指令语气，不要改为陈述句。
            如果原文包含代码片段或命令，原样保留不动。
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

    private func systemPrompt(for style: String) -> String {
        let perStyleKey = SharedSettings.customRewritePromptKey(for: style)
        let perStyleCustom = SharedSettings.defaults.string(forKey: perStyleKey) ?? ""
        if !perStyleCustom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return perStyleCustom
        }
        return Self.defaultSystemPrompt(for: style)
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
            return ratio > 1.6
        }
        if original.count <= 24 {
            return ratio > 1.4
        }
        return ratio > 1.25
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

    private func configuredMaxTokens() -> Int {
        let raw = SharedSettings.defaults.object(forKey: SharedSettings.Keys.llmMaxTokens) as? Int ?? 2048
        return min(4096, max(512, raw))
    }

    private func configuredBaseTimeoutSeconds() -> Double {
        let raw = SharedSettings.defaults.object(forKey: SharedSettings.Keys.llmTimeoutSeconds) as? Double ?? 30
        return min(90, max(15, raw))
    }

    private func configuredRetryCount() -> Int {
        let raw = SharedSettings.defaults.object(forKey: SharedSettings.Keys.llmRetryCount) as? Int ?? 2
        return min(4, max(0, raw))
    }

    private func effectiveMaxTokens(for text: String) -> Int {
        let base = configuredMaxTokens()
        if text.count > 2200 { return max(base, 4096) }
        if text.count > 1200 { return max(base, 3072) }
        return base
    }

    private func effectiveTimeout(for text: String) -> TimeInterval {
        let base = configuredBaseTimeoutSeconds()
        if text.count > 2200 { return max(base, 60) }
        if text.count > 1200 { return max(base, 45) }
        return base
    }

    private func performRequestWithRetry(_ request: URLRequest, retryCount: Int) async throws -> (Data, URLResponse) {
        var lastError: Error?
        var attempts = 0
        while attempts <= retryCount {
            do {
                return try await session.data(for: request)
            } catch {
                lastError = error
                attempts += 1
                if attempts > retryCount { break }
                let delayNanos: UInt64 = attempts == 1 ? 300_000_000 : 700_000_000
                try? await Task.sleep(nanoseconds: delayNanos)
            }
        }
        throw lastError ?? PolishClientError.decodeFailed
    }
}
