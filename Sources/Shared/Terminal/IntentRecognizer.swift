import Foundation

enum IntentType: String, Codable {
    case addCalendar
    case createNote
    case openApp
    case runCommand
    case unrecognized
}

struct RecognizedIntent {
    let type: IntentType
    let title: String
    let detail: String
    let confidence: Double
    let displaySummary: String
}

private struct IntentLLMRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double
    let max_tokens: Int
}

private struct IntentLLMResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }
        let message: Message
    }

    let choices: [Choice]
}

private struct IntentJSON: Decodable {
    let type: String
    let title: String
    let detail: String
    let confidence: Double
}

final class IntentRecognizer {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func recognize(text: String) async -> RecognizedIntent {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return unrecognized(trimmed)
        }

        let defaults = SharedSettings.defaults
        let baseURL = defaults.string(forKey: SharedSettings.Keys.llmAPIBaseURL) ?? "https://oneapi.gemiaude.com/v1"
        let apiKey = defaults.string(forKey: SharedSettings.Keys.llmAPIKey) ?? ""
        let model = defaults.string(forKey: SharedSettings.Keys.llmModel) ?? "gemini-2.5-flash-lite"

        guard apiKey.count >= 10 else {
            return unrecognized(trimmed)
        }

        let normalized = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        let endpoint = normalized.hasSuffix("/chat/completions") ? normalized : "\(normalized)/chat/completions"
        guard let url = URL(string: endpoint) else {
            return unrecognized(trimmed)
        }

        let req = IntentLLMRequest(
            model: model,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: trimmed)
            ],
            temperature: 0.0,
            max_tokens: 512
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            request.httpBody = try JSONEncoder().encode(req)
        } catch {
            return unrecognized(trimmed)
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return unrecognized(trimmed)
            }

            guard
                let decoded = try? JSONDecoder().decode(IntentLLMResponse.self, from: data),
                let content = decoded.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
                !content.isEmpty
            else {
                return unrecognized(trimmed)
            }

            return parseIntentJSON(content, originalText: trimmed)
        } catch {
            return unrecognized(trimmed)
        }
    }

    private func parseIntentJSON(_ jsonString: String, originalText: String) -> RecognizedIntent {
        var cleaned = jsonString
        if cleaned.hasPrefix("```json") {
            cleaned = String(cleaned.dropFirst(7))
        } else if cleaned.hasPrefix("```") {
            cleaned = String(cleaned.dropFirst(3))
        }
        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8),
              let parsed = try? JSONDecoder().decode(IntentJSON.self, from: data) else {
            return unrecognized(originalText)
        }

        guard parsed.confidence >= 0.5 else {
            return unrecognized(originalText)
        }

        let intentType = IntentType(rawValue: parsed.type) ?? .unrecognized
        if intentType == .unrecognized {
            return unrecognized(originalText)
        }

        let summary: String
        switch intentType {
        case .addCalendar:
            summary = "添加日历: \(parsed.title)"
        case .createNote:
            summary = "创建笔记: \(parsed.title)"
        case .openApp:
            summary = "打开应用: \(parsed.title)"
        case .runCommand:
            summary = "执行命令: \(parsed.title)"
        case .unrecognized:
            summary = originalText
        }

        return RecognizedIntent(
            type: intentType,
            title: parsed.title,
            detail: parsed.detail,
            confidence: parsed.confidence,
            displaySummary: summary
        )
    }

    private func unrecognized(_ text: String) -> RecognizedIntent {
        RecognizedIntent(
            type: .unrecognized,
            title: text,
            detail: "",
            confidence: 0,
            displaySummary: text
        )
    }

    private var systemPrompt: String {
        """
        你是语音命令意图识别器。用户会说出一个命令，你需要识别意图并输出严格的JSON。

        支持的意图类型：
        1. addCalendar - 添加日历事件（如"添加明天下午3点的会议到日历"）
        2. createNote - 创建笔记（如"创建笔记 购物清单"、"记一下明天要买牛奶"）
        3. openApp - 打开应用程序（如"打开Safari"、"打开记事本"、"打开微信"）
        4. runCommand - 执行终端命令（如"执行ls"、"运行 brew update"）

        输出格式（只输出JSON，不要其他内容）：
        {"type":"addCalendar","title":"会议","detail":"明天下午3点","confidence":0.95}

        字段说明：
        - type: 意图类型，必须是上述4种之一
        - title: 简短标题
        - detail: 详细信息（日期时间/笔记内容/应用名/命令内容）
        - confidence: 置信度 0.0-1.0

        【openApp 特别规则】：
        title 字段必须填写应用的标准英文名或系统名称，不要用中文别名。常见映射：
        - 记事本/备忘录/苹果记事本 → title:"Notes"
        - 日历 → title:"Calendar"
        - 邮件/邮箱 → title:"Mail"
        - 信息/消息/短信 → title:"Messages"
        - 浏览器/Safari浏览器 → title:"Safari"
        - 设置/系统设置 → title:"System Settings"
        - 终端/命令行 → title:"Terminal"
        - 访达/文件管理器 → title:"Finder"
        - 音乐/苹果音乐 → title:"Music"
        - 照片/相册 → title:"Photos"
        - 提醒事项/提醒 → title:"Reminders"
        - 计算器 → title:"Calculator"
        - 微信 → title:"WeChat"
        - 钉钉 → title:"DingTalk"
        - 飞书 → title:"Lark"
        - 谷歌浏览器 → title:"Google Chrome"
        - 火狐浏览器 → title:"Firefox"
        - 网易云音乐 → title:"NeteaseMusic"
        如果用户直接说英文名（如Safari, Chrome），保留原样。
        detail 字段填中文原始表述。

        【createNote 规则】：
        title 填笔记标题，detail 填笔记正文内容。如用户说"记一下明天要买牛奶"，title:"购物备忘", detail:"明天要买牛奶"。

        如果无法识别意图，输出：
        {"type":"unrecognized","title":"","detail":"","confidence":0.0}

        只输出JSON，不要输出任何其他文字。
        """
    }
}
