import Foundation
import EventKit

final class CalendarAgent: VoiceAgentPlugin {
    var intentTypes: [IntentType] { [.addCalendar] }

    private let store = EKEventStore()

    func execute(intent: RecognizedIntent) async -> AgentResponse {
        let granted: Bool
        if #available(macOS 14.0, *) {
            granted = (try? await store.requestFullAccessToEvents()) ?? false
        } else {
            granted = await withCheckedContinuation { continuation in
                store.requestAccess(to: .event) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        }

        guard granted else {
            return .simple("未授权日历访问。请在 系统设置 > 隐私与安全性 > 日历 中允许 VoiceInput。", success: false)
        }

        let event = EKEvent(eventStore: store)
        event.title = intent.title
        event.calendar = store.defaultCalendarForNewEvents

        let (startDate, endDate) = parseDateFromDetail(intent.detail)
        event.startDate = startDate
        event.endDate = endDate

        do {
            try store.save(event, span: .thisEvent)
            let formatter = DateFormatter()
            formatter.dateFormat = "MM月dd日 HH:mm"
            let dateStr = formatter.string(from: startDate)
            return .simple("已添加日历事件「\(intent.title)」于 \(dateStr)")
        } catch {
            return .simple("日历创建失败: \(error.localizedDescription)", success: false)
        }
    }

    private func parseDateFromDetail(_ detail: String) -> (start: Date, end: Date) {
        let now = Date()
        let calendar = Calendar.current

        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
            let range = NSRange(detail.startIndex..<detail.endIndex, in: detail)
            let matches = detector.matches(in: detail, range: range)
            if let match = matches.first, let date = match.date {
                let end = calendar.date(byAdding: .hour, value: 1, to: date) ?? date
                return (date, end)
            }
        }

        var targetDate = now
        let lowered = detail.lowercased()

        if lowered.contains("明天") {
            targetDate = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        } else if lowered.contains("后天") {
            targetDate = calendar.date(byAdding: .day, value: 2, to: now) ?? now
        } else if lowered.contains("下周") || lowered.contains("下个星期") {
            targetDate = calendar.date(byAdding: .weekOfYear, value: 1, to: now) ?? now
        }

        var hour = 9
        var minute = 0

        let timePatterns: [(pattern: String, hourOffset: Int)] = [
            ("上午(\\d{1,2})(?:点|时)(\\d{1,2})?(?:分)?", 0),
            ("下午(\\d{1,2})(?:点|时)(\\d{1,2})?(?:分)?", 12),
            ("晚上(\\d{1,2})(?:点|时)(\\d{1,2})?(?:分)?", 12),
            ("(\\d{1,2})(?:点|时)(\\d{1,2})?(?:分)?", 0)
        ]

        for tp in timePatterns {
            if let regex = try? NSRegularExpression(pattern: tp.pattern),
               let match = regex.firstMatch(in: detail, range: NSRange(detail.startIndex..<detail.endIndex, in: detail)) {
                if let hourRange = Range(match.range(at: 1), in: detail) {
                    let h = Int(detail[hourRange]) ?? 9
                    hour = h + (h < 12 ? tp.hourOffset : 0)
                }
                if match.numberOfRanges > 2, let minuteRange = Range(match.range(at: 2), in: detail) {
                    minute = Int(detail[minuteRange]) ?? 0
                }
                break
            }
        }

        var components = calendar.dateComponents([.year, .month, .day], from: targetDate)
        components.hour = hour
        components.minute = minute
        let startDate = calendar.date(from: components) ?? now
        let endDate = calendar.date(byAdding: .hour, value: 1, to: startDate) ?? startDate

        return (startDate, endDate)
    }
}
