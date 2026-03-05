import Foundation
import EventKit

final class RemindersAgent: VoiceAgentPlugin {
    var intentTypes: [IntentType] { [.addReminder] }

    private let store = EKEventStore()

    func execute(intent: RecognizedIntent) async -> AgentResponse {
        let granted: Bool
        if #available(macOS 14.0, *) {
            granted = (try? await store.requestFullAccessToReminders()) ?? false
        } else {
            granted = await withCheckedContinuation { continuation in
                store.requestAccess(to: .reminder) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        }

        guard granted else {
            return .simple("未授权提醒事项访问。请在 系统设置 > 隐私与安全性 > 提醒事项 中允许 VoiceInput。", success: false)
        }

        guard let calendar = store.defaultCalendarForNewReminders() else {
            return .simple("无法获取默认提醒事项列表", success: false)
        }

        let reminder = EKReminder(eventStore: store)
        reminder.title = intent.detail.isEmpty ? intent.title : intent.detail
        reminder.calendar = calendar

        // Parse due date from title (which includes time description)
        if let dueDate = parseDueDateFromTitle(intent.title) {
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )
            reminder.dueDateComponents = components

            let alarm = EKAlarm(absoluteDate: dueDate)
            reminder.addAlarm(alarm)
        }

        do {
            try store.save(reminder, commit: true)
            let dueDateStr: String
            if let due = reminder.dueDateComponents,
               let date = Calendar.current.date(from: due) {
                let formatter = DateFormatter()
                formatter.dateFormat = "MM月dd日 HH:mm"
                dueDateStr = "，提醒时间: \(formatter.string(from: date))"
            } else {
                dueDateStr = ""
            }
            return .simple("已添加提醒「\(reminder.title ?? "")」\(dueDateStr)")
        } catch {
            return .simple("提醒事项创建失败: \(error.localizedDescription)", success: false)
        }
    }

    private func parseDueDateFromTitle(_ title: String) -> Date? {
        // Use NSDataDetector to extract date/time from natural language
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return nil
        }
        let range = NSRange(title.startIndex..<title.endIndex, in: title)
        let matches = detector.matches(in: title, range: range)
        return matches.first?.date
    }
}
