import Foundation
import AppKit

enum SearchEngine {
    case google
    case baidu
    case bing

    var baseURL: String {
        switch self {
        case .google: return "https://www.google.com/search?q="
        case .baidu: return "https://www.baidu.com/s?wd="
        case .bing: return "https://www.bing.com/search?q="
        }
    }

    var displayName: String {
        switch self {
        case .google: return "Google"
        case .baidu: return "百度"
        case .bing: return "Bing"
        }
    }
}

final class WebSearchAgent: VoiceAgentPlugin {
    var intentTypes: [IntentType] { [.webSearch] }

    func execute(intent: RecognizedIntent) async -> AgentResponse {
        let query = intent.detail.isEmpty ? intent.title : intent.detail
        let engine = detectEngine(query)
        let cleanQuery = stripEnginePrefix(query)

        guard !cleanQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .simple("搜索词为空", success: false)
        }

        guard let encoded = cleanQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: engine.baseURL + encoded) else {
            return .simple("无法构建搜索 URL", success: false)
        }

        NSWorkspace.shared.open(url)
        let truncated = truncate(cleanQuery, maxLength: 30)
        return .simple("正在搜索「\(truncated)」")
    }

    private func detectEngine(_ query: String) -> SearchEngine {
        let lower = query.lowercased()
        if lower.hasPrefix("百度") || lower.contains("百度搜索") || lower.contains("用百度") {
            return .baidu
        }
        if lower.hasPrefix("bing") || lower.contains("bing搜索") || lower.contains("用bing") {
            return .bing
        }
        if lower.hasPrefix("google") || lower.contains("谷歌") || lower.contains("用google") || lower.contains("用谷歌") {
            return .google
        }
        return .google
    }

    private func stripEnginePrefix(_ query: String) -> String {
        var q = query
        let prefixes = ["百度搜索", "百度一下", "百度", "Google搜索", "google搜索", "Google", "google",
                        "谷歌搜索", "谷歌", "Bing搜索", "bing搜索", "Bing", "bing",
                        "用百度搜索", "用百度搜", "用百度", "用谷歌搜索", "用谷歌搜", "用谷歌",
                        "用Google搜索", "用google搜索", "用Google", "用google",
                        "用Bing搜索", "用bing搜索", "用Bing", "用bing",
                        "搜索", "搜一下", "搜"]
        for prefix in prefixes {
            if q.hasPrefix(prefix) {
                q = String(q.dropFirst(prefix.count))
                break
            }
        }
        return q.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func truncate(_ text: String, maxLength: Int) -> String {
        if text.count <= maxLength { return text }
        return String(text.prefix(maxLength)) + "..."
    }
}
