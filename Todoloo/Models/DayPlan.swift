import Foundation
import SwiftData

/// Derived planning data. Estimates describe elapsed time, including across clock changes.
struct DayPlan {
    let overdue: [TodoItem]
    let scheduled: [TodoItem]
    let flexible: [TodoItem]
    let estimatedMinutes: Int
    let missingEstimates: Int
    let overlappingIDs: Set<PersistentIdentifier>

    init(items: [TodoItem], date: Date, calendar: Calendar = .current) {
        let dayStart = calendar.startOfDay(for: date)
        let active = items.filter { !$0.isCompleted }
        let today = active.filter { $0.dueDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false }
        overdue = TaskSort.dueDate.ordered(active.filter { ($0.dueDate ?? .distantFuture) < dayStart })
        scheduled = today.filter { $0.scheduledStart(calendar: calendar) != nil }.sorted {
            if $0.startMinuteOfDay == $1.startMinuteOfDay { return $0.createdAt < $1.createdAt }
            return ($0.startMinuteOfDay ?? 0) < ($1.startMinuteOfDay ?? 0)
        }
        flexible = today.filter { $0.scheduledStart(calendar: calendar) == nil }
        estimatedMinutes = today.reduce(0) { $0 + max($1.durationMinutes ?? 0, 0) }
        missingEstimates = today.filter { ($0.durationMinutes ?? 0) <= 0 }.count

        let intervals = active.compactMap { item -> (TodoItem, DateInterval)? in
            guard let interval = item.plannedInterval(calendar: calendar) else { return nil }
            return (item, interval)
        }.sorted { $0.1.start < $1.1.start }
        var furthest: (TodoItem, DateInterval)?
        var conflicts = Set<PersistentIdentifier>()
        for (item, interval) in intervals {
            if let (other, previous) = furthest, previous.end > interval.start {
                conflicts.insert(other.persistentModelID)
                conflicts.insert(item.persistentModelID)
            }
            if furthest == nil || interval.end > furthest!.1.end { furthest = (item, interval) }
        }
        overlappingIDs = conflicts
    }
}

extension TodoItem {
    func plannedInterval(calendar: Calendar = .current) -> DateInterval? {
        guard let start = scheduledStart(calendar: calendar),
              let durationMinutes, durationMinutes > 0 else { return nil }
        return DateInterval(start: start, duration: Double(durationMinutes) * 60)
    }

    func plannedTimeLabel(calendar: Calendar = .current) -> String? {
        guard let startTimeLabel else { return nil }
        guard let interval = plannedInterval(calendar: calendar) else { return startTimeLabel }
        let clock = calendar.dateComponents([.hour, .minute], from: interval.end)
        let end = Self.timeLabel((clock.hour ?? 0) * 60 + (clock.minute ?? 0))
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: interval.start),
                                           to: calendar.startOfDay(for: interval.end)).day ?? 0
        return "\(startTimeLabel)–\(end)" + (days > 0 ? " (+\(days)d)" : "")
    }

    func overlaps(_ other: TodoItem, calendar: Calendar = .current) -> Bool {
        guard self !== other, !isCompleted, !other.isCompleted,
              let lhs = plannedInterval(calendar: calendar),
              let rhs = other.plannedInterval(calendar: calendar) else { return false }
        // Touching boundaries are consecutive tasks, not conflicts.
        return lhs.start < rhs.end && rhs.start < lhs.end
    }

    static func estimateLabel(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let remainder = minutes % 60
        return "\(minutes / 60) hr" + (remainder == 0 ? "" : " \(remainder) min")
    }
}
