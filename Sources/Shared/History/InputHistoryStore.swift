import Foundation

enum InputDeliveryStatus: String, Codable {
    case inserted
    case pendingCopy = "pending_copy"
    case copied
}

struct InputHistoryItem: Identifiable, Codable {
    let id: String
    let timestamp: TimeInterval
    let originalText: String
    let processedText: String
    let finalText: String
    let style: String
    let status: InputDeliveryStatus
    let note: String

    init(
        id: String = UUID().uuidString,
        timestamp: TimeInterval = Date().timeIntervalSince1970,
        originalText: String,
        processedText: String,
        finalText: String,
        style: String,
        status: InputDeliveryStatus,
        note: String = ""
    ) {
        self.id = id
        self.timestamp = timestamp
        self.originalText = originalText
        self.processedText = processedText
        self.finalText = finalText
        self.style = style
        self.status = status
        self.note = note
    }
}

final class InputHistoryStore {
    static let shared = InputHistoryStore()
    private let defaults = SharedSettings.defaults
    private let key = "inputHistoryRecords"
    private let maxCount = 100
    private let queue = DispatchQueue(label: "com.voiceinput.history.queue")

    private init() {}

    func all() -> [InputHistoryItem] {
        queue.sync {
            loadLocked()
        }
    }

    func append(_ item: InputHistoryItem) {
        queue.sync {
            let enabled = defaults.object(forKey: SharedSettings.Keys.saveHistoryEnabled) as? Bool ?? true
            guard enabled else { return }
            var items = loadLocked()
            items.insert(item, at: 0)
            if items.count > maxCount {
                items = Array(items.prefix(maxCount))
            }
            saveLocked(items)
        }
    }

    func clear() {
        queue.sync {
            defaults.removeObject(forKey: key)
        }
    }

    private func loadLocked() -> [InputHistoryItem] {
        guard let data = defaults.data(forKey: key) else { return [] }
        guard let decoded = try? JSONDecoder().decode([InputHistoryItem].self, from: data) else { return [] }
        return decoded
    }

    private func saveLocked(_ items: [InputHistoryItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: key)
    }
}
