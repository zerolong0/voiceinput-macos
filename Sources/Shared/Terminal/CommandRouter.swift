import Foundation

final class CommandRouter {
    private let calendarAgent = CalendarAgent()
    private let notesAgent = NotesAgent()
    private let appLauncherAgent = AppLauncherAgent()
    private let cliAgent = CLIAgent()
    private let systemControlAgent = SystemControlAgent()
    private let webSearchAgent = WebSearchAgent()

    func execute(_ intent: RecognizedIntent) async -> CommandResult {
        switch intent.type {
        case .addCalendar:
            return await calendarAgent.execute(intent: intent)
        case .createNote:
            return await notesAgent.execute(intent: intent)
        case .openApp:
            return await appLauncherAgent.execute(intent: intent)
        case .runCommand:
            return await cliAgent.execute(intent: intent)
        case .systemControl:
            return await systemControlAgent.execute(intent: intent)
        case .webSearch:
            return await webSearchAgent.execute(intent: intent)
        case .unrecognized:
            return CommandResult(success: false, message: "无法识别该命令")
        }
    }
}
