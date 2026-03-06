import Foundation

enum VoiceAgentStage: String {
    case idle
    case arming
    case listening
    case recognizing
    case previewing
    case confirming
    case executing
    case result
    case error
}

final class VoiceAgentSessionStore: ObservableObject {
    static let shared = VoiceAgentSessionStore()

    @Published var stage: VoiceAgentStage = .idle
    @Published var stageText: String = "就绪"
    @Published var liveText: String = ""
    @Published var intentText: String = ""
    @Published var resultText: String = ""
    @Published var updatedAt: TimeInterval = Date().timeIntervalSince1970

    private init() {}

    func beginSession(status: String) {
        DispatchQueue.main.async {
            self.stage = .arming
            self.stageText = status
            self.liveText = ""
            self.intentText = ""
            self.resultText = ""
            self.updatedAt = Date().timeIntervalSince1970
        }
    }

    func setStage(_ stage: VoiceAgentStage, text: String) {
        DispatchQueue.main.async {
            self.stage = stage
            self.stageText = text
            self.updatedAt = Date().timeIntervalSince1970
        }
    }

    func updateLiveText(_ text: String) {
        DispatchQueue.main.async {
            self.liveText = text
            self.updatedAt = Date().timeIntervalSince1970
        }
    }

    func updateIntentText(_ text: String) {
        DispatchQueue.main.async {
            self.intentText = text
            self.updatedAt = Date().timeIntervalSince1970
        }
    }

    func updateResultText(_ text: String) {
        DispatchQueue.main.async {
            self.resultText = text
            self.updatedAt = Date().timeIntervalSince1970
        }
    }

    func reset() {
        DispatchQueue.main.async {
            self.stage = .idle
            self.stageText = "就绪"
            self.liveText = ""
            self.intentText = ""
            self.resultText = ""
            self.updatedAt = Date().timeIntervalSince1970
        }
    }
}
