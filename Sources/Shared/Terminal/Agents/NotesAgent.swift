import Foundation

final class NotesAgent {
    func execute(intent: RecognizedIntent) async -> CommandResult {
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
                return CommandResult(success: false, message: "AppleScript 创建失败")
            }

            var error: NSDictionary?
            script.executeAndReturnError(&error)

            if let error = error {
                let msg = error[NSAppleScript.errorMessage] as? String ?? "未知错误"
                return CommandResult(success: false, message: "笔记创建失败: \(msg)")
            }

            return CommandResult(success: true, message: "已创建笔记「\(intent.title)」")
        }
    }

    private func sanitizeForAppleScript(_ input: String) -> String {
        input
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
