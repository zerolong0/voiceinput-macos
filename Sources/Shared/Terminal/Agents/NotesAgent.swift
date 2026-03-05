import Foundation

final class NotesAgent: VoiceAgentPlugin {
    var intentTypes: [IntentType] { [.createNote] }

    func execute(intent: RecognizedIntent) async -> AgentResponse {
        let title = sanitizeForAppleScript(intent.title)
        let body = sanitizeForAppleScript(intent.detail)

        let scriptSource: String
        if body.isEmpty {
            scriptSource = """
            tell application "Notes"
                activate
                make new note at folder "Notes" with properties {name:"\(title)", body:"\(title)"}
            end tell
            """
        } else {
            scriptSource = """
            tell application "Notes"
                activate
                make new note at folder "Notes" with properties {name:"\(title)", body:"\(body)"}
            end tell
            """
        }

        return await MainActor.run {
            guard let script = NSAppleScript(source: scriptSource) else {
                return AgentResponse.simple("AppleScript 创建失败", success: false)
            }

            var error: NSDictionary?
            script.executeAndReturnError(&error)

            if let error = error {
                let msg = error[NSAppleScript.errorMessage] as? String ?? "未知错误"
                return AgentResponse.simple("笔记创建失败: \(msg)", success: false)
            }

            return AgentResponse.simple("已创建笔记「\(intent.title)」")
        }
    }

    private func sanitizeForAppleScript(_ input: String) -> String {
        input
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
