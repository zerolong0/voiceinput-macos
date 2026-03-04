import Foundation

final class CLIAgent {
    private static let dangerousPatterns: [String] = [
        "rm -rf /", "rm -rf ~", "rm -rf /*",
        "sudo rm", "mkfs", "dd if=",
        ":(){:|:&};:", "chmod -R 777 /",
        "curl.*|.*sh", "wget.*|.*sh",
        "> /dev/sda", "mv /* /dev/null"
    ]

    func execute(intent: RecognizedIntent) async -> CommandResult {
        let command = intent.detail.isEmpty ? intent.title : intent.detail
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return CommandResult(success: false, message: "未指定命令")
        }

        if isDangerous(trimmed) {
            return CommandResult(success: false, message: "该命令被安全策略拒绝: \(truncate(trimmed, maxLength: 60))")
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
                let output = outStr.isEmpty ? "(无输出)" : truncate(outStr, maxLength: 200)
                return CommandResult(success: true, message: output)
            } else {
                let output = errStr.isEmpty ? outStr : errStr
                return CommandResult(success: false, message: "退出码 \(process.terminationStatus): \(truncate(output, maxLength: 200))")
            }
        } catch {
            return CommandResult(success: false, message: "命令执行失败: \(error.localizedDescription)")
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
