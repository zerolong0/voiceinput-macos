import Foundation

final class CLIAgent: VoiceAgentPlugin {
    var intentTypes: [IntentType] { [.runCommand] }

    private static let dangerousPatterns: [String] = [
        "rm -rf /", "rm -rf ~", "rm -rf /*",
        "sudo rm", "mkfs", "dd if=",
        ":(){:|:&};:", "chmod -R 777 /",
        "curl.*|.*sh", "wget.*|.*sh",
        "> /dev/sda", "mv /* /dev/null"
    ]

    func execute(intent: RecognizedIntent) async -> AgentResponse {
        let command = intent.detail.isEmpty ? intent.title : intent.detail
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return .simple("未指定命令", success: false)
        }

        if isDangerous(trimmed) {
            return .simple("该命令被安全策略拒绝: \(truncate(trimmed, maxLength: 60))", success: false)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", trimmed]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()

            let outData = stdout.fileHandleForReading.readDataToEndOfFile()
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()

            let outStr = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if process.terminationStatus == 0 {
                let output = outStr.isEmpty ? "(无输出)" : outStr
                let shortOutput = truncate(output, maxLength: 80)
                // Use rich content if output is long
                if output.count > 80 {
                    return AgentResponse(success: true, title: "命令执行成功", body: output, actions: [], contentType: .text)
                }
                return .simple(shortOutput)
            } else {
                let output = errStr.isEmpty ? outStr : errStr
                return .simple("退出码 \(process.terminationStatus): \(truncate(output, maxLength: 200))", success: false)
            }
        } catch {
            return .simple("命令执行失败: \(error.localizedDescription)", success: false)
        }
    }

    private func isDangerous(_ command: String) -> Bool {
        let lowered = command.lowercased()
        return Self.dangerousPatterns.contains { pattern in
            if let regex = try? NSRegularExpression(pattern: NSRegularExpression.escapedPattern(for: pattern), options: .caseInsensitive) {
                let range = NSRange(lowered.startIndex..<lowered.endIndex, in: lowered)
                return regex.firstMatch(in: lowered, range: range) != nil
            }
            return lowered.contains(pattern.lowercased())
        }
    }

    private func truncate(_ text: String, maxLength: Int) -> String {
        if text.count <= maxLength { return text }
        return String(text.prefix(maxLength)) + "..."
    }
}
