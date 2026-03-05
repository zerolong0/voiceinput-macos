import Foundation

final class CommandRouter {
    private let registry = PluginRegistry()

    init() {
        registry.register(CalendarAgent())
        registry.register(NotesAgent())
        registry.register(AppLauncherAgent())
        registry.register(CLIAgent())
        registry.register(SystemControlAgent())
        registry.register(WebSearchAgent())
        registry.register(WeatherAgent())
        registry.register(ContactsAgent())
        registry.register(RemindersAgent())
    }

    func execute(intent: RecognizedIntent) async -> AgentResponse {
        guard let plugin = registry.plugin(for: intent.type) else {
            return .simple("无法处理该意图", success: false)
        }
        return await plugin.execute(intent: intent)
    }
}
