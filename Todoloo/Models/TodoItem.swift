import Foundation
import SwiftData

@Model
final class TodoItem {
    var title: String
    var notes: String
    var isCompleted: Bool
    var createdAt: Date
    var completedAt: Date?
    var dueDate: Date? = nil
    var listName: String = "Personal"
    var isImportant: Bool = false
    var durationMinutes: Int? = nil
    var startMinuteOfDay: Int? = nil
    var remindersEnabled: Bool = true
    var reminderIdentifier: String? = nil

    static let startTimeOptions = Array(stride(from: 0, to: 1440, by: 15))

    static func timeLabel(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    var startTimeLabel: String? { startMinuteOfDay.map(Self.timeLabel) }

    func setStartTime(_ minute: Int?) {
        startMinuteOfDay = minute.map { min(max($0, 0), 1425) / 15 * 15 }
        if minute != nil {
            if dueDate == nil { dueDate = Calendar.current.startOfDay(for: .now) }
            if reminderIdentifier == nil { reminderIdentifier = UUID().uuidString }
        }
    }

    func scheduledStart(calendar: Calendar = .current) -> Date? {
        guard let dueDate, let minute = startMinuteOfDay,
              Self.startTimeOptions.contains(minute),
              let start = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0,
                                        of: dueDate, matchingPolicy: .strict, repeatedTimePolicy: .first),
              calendar.isDate(start, inSameDayAs: dueDate) else { return nil }
        return start
    }

    func reminderPlan(now: Date = .now, calendar: Calendar = .current) -> TaskReminder? {
        guard remindersEnabled, !isCompleted, let reminderIdentifier,
              let start = scheduledStart(calendar: calendar) else { return nil }
        let fireDate = start.addingTimeInterval(-15 * 60)
        guard fireDate > now else { return nil }
        return TaskReminder(id: "todoloo.task." + reminderIdentifier, title: title, start: start, fireDate: fireDate)
    }

    var durationLabel: String? {
        guard let minutes = durationMinutes, minutes > 0 else { return nil }
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return "\(minutes) min" }
        return remainder == 0 ? "\(hours) hr" : "\(hours) hr \(remainder) min"
    }

    /// Only an explicit duration at the end is interpreted; other parentheses remain part of the title.
    static func parseDraft(_ draft: String) -> (title: String, durationMinutes: Int?, startMinuteOfDay: Int?) {
        var title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        var duration: Int?
        var startMinute: Int?
        // Accept either order: “Read (09:15) (30mins)” or “Read (30mins) (09:15)”.
        for _ in 0..<2 {
            if duration == nil {
                let parsed = parseDurationSuffix(title)
                if let minutes = parsed.durationMinutes {
                    title = parsed.title
                    duration = minutes
                    continue
                }
            }
            if startMinute == nil,
               let range = title.range(of: #"\s*\(\s*\d{1,2}:\d{2}\s*\)\s*$"#, options: .regularExpression) {
                let raw = title[range].trimmingCharacters(in: CharacterSet(charactersIn: "() \t\n"))
                let parts = raw.split(separator: ":").compactMap { Int($0) }
                let stripped = String(title[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                if parts.count == 2, (0...23).contains(parts[0]), [0, 15, 30, 45].contains(parts[1]), !stripped.isEmpty {
                    startMinute = parts[0] * 60 + parts[1]
                    title = stripped
                    continue
                }
            }
            break
        }
        return (title, duration, startMinute)
    }

    private static func parseDurationSuffix(_ draft: String) -> (title: String, durationMinutes: Int?) {
        let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"\s*\(\s*(?:(\d+)\s*h(?:ours?|rs?)?\s*)?(?:(\d+)\s*m(?:in(?:ute)?s?)?\s*)?\)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
              let suffix = Range(match.range, in: title) else { return (title, nil) }
        func number(_ group: Int) -> Int? {
            guard let range = Range(match.range(at: group), in: title) else { return 0 }
            return Int(title[range])
        }
        guard let hours = number(1), let minutes = number(2), hours <= 24, minutes <= 1440 else { return (title, nil) }
        let duration = hours * 60 + minutes
        let stripped = String(title[..<suffix.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty, (1...1440).contains(duration) else { return (title, nil) }
        return (stripped, duration)
    }

    init(title: String, notes: String = "") {
        self.title = title
        self.notes = notes
        self.isCompleted = false
        self.createdAt = .now
        self.completedAt = nil
    }

    func isOverdue(relativeTo date: Date = .now) -> Bool {
        guard let dueDate, !isCompleted else { return false }
        return dueDate < Calendar.current.startOfDay(for: date)
    }

    func setCompleted(_ completed: Bool) {
        isCompleted = completed
        completedAt = completed ? .now : nil
    }
}
