import Foundation

// MARK: - AgentResponse

struct AgentResponse {
    let success: Bool
    let title: String
    let body: String
    let actions: [AgentAction]
    let contentType: ContentType

    enum ContentType {
        case text
        case markdown
        case keyValue
    }

    static func simple(_ message: String, success: Bool = true) -> AgentResponse {
        AgentResponse(success: success, title: message, body: "", actions: [], contentType: .text)
    }
}

// MARK: - AgentAction

struct AgentAction {
    let label: String
    let systemImage: String
    let handler: () -> Void
}

// MARK: - VoiceAgentPlugin

protocol VoiceAgentPlugin: AnyObject {
    var intentTypes: [IntentType] { get }
    func execute(intent: RecognizedIntent) async -> AgentResponse
}

// MARK: - PluginRegistry

final class PluginRegistry {
    private var plugins: [IntentType: any VoiceAgentPlugin] = [:]

    func register(_ plugin: any VoiceAgentPlugin) {
        for intentType in plugin.intentTypes {
            plugins[intentType] = plugin
        }
    }

    func plugin(for type: IntentType) -> (any VoiceAgentPlugin)? {
        plugins[type]
    }
}
