import Foundation

enum RealtimeStage: String {
    case idle
    case arming
    case listening
    case transcribing
    case rewriting
    case inserted
    case pendingCopy
    case permissionBlocked
    case failed
}

final class RealtimeSessionStore: ObservableObject {
    static let shared = RealtimeSessionStore()

    @Published var stage: RealtimeStage = .idle
    @Published var stageText: String = "就绪"
    @Published var originalLiveText: String = ""
    @Published var rewrittenText: String = ""
    @Published var updatedAt: TimeInterval = Date().timeIntervalSince1970

    private init() {}

    func setStage(_ stage: RealtimeStage, text: String) {
        DispatchQueue.main.async {
            self.stage = stage
            self.stageText = text
            self.updatedAt = Date().timeIntervalSince1970
        }
    }

    func updateOriginalLiveText(_ text: String) {
        DispatchQueue.main.async {
            self.originalLiveText = text
            self.updatedAt = Date().timeIntervalSince1970
        }
    }

    func updateRewrittenText(_ text: String) {
        DispatchQueue.main.async {
            self.rewrittenText = text
            self.updatedAt = Date().timeIntervalSince1970
        }
    }

    func reset() {
        DispatchQueue.main.async {
            self.stage = .idle
            self.stageText = "就绪"
            self.originalLiveText = ""
            self.rewrittenText = ""
            self.updatedAt = Date().timeIntervalSince1970
        }
    }
}
