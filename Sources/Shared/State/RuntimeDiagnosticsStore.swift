import Foundation

enum RuntimeDiagnosticsStore {
    private static let key = "runtimeDiagnostics.events"
    private static let maxCount = 60
    private static let queue = DispatchQueue(label: "com.voiceinput.runtime-diagnostics")

    static func record(_ channel: String, _ message: String) {
        queue.async {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let line = "[\(timestamp)] [\(channel)] \(message)"
            var items = SharedSettings.defaults.stringArray(forKey: key) ?? []
            items.append(line)
            if items.count > maxCount {
                items.removeFirst(items.count - maxCount)
            }
            SharedSettings.defaults.set(items, forKey: key)
        }
    }

    static func clear() {
        queue.sync {
            SharedSettings.defaults.set([], forKey: key)
        }
    }
}
