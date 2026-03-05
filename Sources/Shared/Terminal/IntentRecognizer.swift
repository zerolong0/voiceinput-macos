import Foundation

enum RiskLevel {
    case safe       // 直接执行，零 UI
    case low        // 0.5s 闪显后自动执行
    case medium     // 语音+按钮确认
    case dangerous  // 仅按钮确认（禁用语音快捷确认）
}

enum IntentType: String, Codable {
    case addCalendar
    case createNote
    case openApp
    case runCommand
    case systemControl
    case webSearch
    case unrecognized

    var riskLevel: RiskLevel {
        switch self {
        case .openApp:        return .safe
        case .webSearch:      return .safe
        case .createNote:     return .low
        case .addCalendar:    return .low
        case .systemControl:  return .medium
        case .runCommand:     return .dangerous
        case .unrecognized:   return .medium
        }
    }
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

struct IntentContext {
    let appName: String?
    let bundleID: String?
    let windowTitle: String?
    let scene: AppScene
    static let empty = IntentContext(appName: nil, bundleID: nil, windowTitle: nil, scene: .unknown)
}

final class IntentRecognizer {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func recognize(text: String, context: IntentContext = .empty) async -> RecognizedIntent {
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

        var effectivePrompt = systemPrompt
        if context.appName != nil || context.windowTitle != nil {
            var block = "\n\n【当前用户环境】\n"
            if let app = context.appName { block += "- 前台应用: \(app)\n" }
            if let bid = context.bundleID { block += "- Bundle ID: \(bid)\n" }
            if let title = context.windowTitle { block += "- 窗口标题: \(title)\n" }
            block += "- 场景: \(context.scene.displayName)\n"
            block += "请根据当前环境优化意图识别。\n"
            effectivePrompt += block
        }

        let req = IntentLLMRequest(
            model: model,
            messages: [
                .init(role: "system", content: effectivePrompt),
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
        case .systemControl:
            summary = "系统控制: \(parsed.title)"
        case .webSearch:
            summary = "搜索: \(parsed.title)"
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

    static var defaultSystemPrompt: String {
        """
        你是语音命令意图识别器。用户会说出一个命令，你需要识别意图并输出严格的JSON。

        支持的意图类型：
        1. addCalendar - 添加日历事件（如"添加明天下午3点的会议到日历"）
        2. createNote - 创建笔记（如"创建笔记 购物清单"、"记一下明天要买牛奶"）
        3. openApp - 打开应用程序（如"打开Safari"、"打开记事本"、"打开微信"）
        4. runCommand - 执行终端命令（如"执行ls"、"运行 brew update"）
        5. systemControl - 系统控制（如"音量调到50"、"静音"、"深色模式"、"锁屏"、"截图"、"关WiFi"）
        6. webSearch - 搜索网页（如"搜索天气预报"、"百度量子计算"、"Google Swift并发"）

        输出格式（只输出JSON，不要其他内容）：
        {"type":"addCalendar","title":"会议","detail":"明天下午3点","confidence":0.95}

        字段说明：
        - type: 意图类型，必须是上述6种之一
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

        【systemControl 规则】：
        title 填操作描述，detail 填结构化动作：
        - 音量: "volume_up" / "volume_down" / "mute" / "unmute" / "set_volume:数字"
        - 亮度: "brightness_up" / "brightness_down"
        - 深色模式: "toggle_dark_mode"
        - 锁屏: "lock_screen"  ·  休眠: "sleep"
        - 勿扰: "toggle_dnd"  ·  截图: "screenshot" / "screenshot_clipboard"
        - WiFi: "toggle_wifi"

        【webSearch 规则】：
        title 填搜索摘要，detail 填完整搜索词。
        用户指定引擎（"百度"/"Google"）时保留在 detail 中。

        如果无法识别意图，输出：
        {"type":"unrecognized","title":"","detail":"","confidence":0.0}

        只输出JSON，不要输出任何其他文字。
        """
    }

    private var systemPrompt: String {
        let custom = SharedSettings.defaults.string(forKey: SharedSettings.Keys.customIntentPrompt) ?? ""
        if !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return custom
        }
        return Self.defaultSystemPrompt
    }
}
