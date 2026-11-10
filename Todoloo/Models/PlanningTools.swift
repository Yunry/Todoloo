import Foundation
import SwiftData

enum RoutineRule: String, CaseIterable, Identifiable {
    case none, daily, weekdays, weekly, afterDay, afterWeek
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: "Never"
        case .daily: "Every day"
        case .weekdays: "Every weekday"
        case .weekly: "Every week"
        case .afterDay: "1 day after completion"
        case .afterWeek: "1 week after completion"
        }
    }

    func nextDate(for item: TodoItem, now: Date, calendar: Calendar) -> Date? {
        guard self != .none else { return nil }
        let today = calendar.startOfDay(for: now)
        let original = calendar.startOfDay(for: item.dueDate ?? now)
        let relative = self == .afterDay || self == .afterWeek
        let threshold = relative ? today : max(today, original)
        var candidate = relative ? today : original
        let step = self == .weekly || self == .afterWeek ? 7 : 1
        // Jump over missed weeks instead of creating a backlog of occurrences.
        if !relative && step == 7 {
            let distance = calendar.dateComponents([.day], from: original, to: threshold).day ?? 0
            candidate = calendar.date(byAdding: .day, value: max(distance / 7, 0) * 7, to: original) ?? original
        } else if step == 1 { candidate = threshold }
        for _ in 0..<400 {
            guard let next = calendar.date(byAdding: .day, value: step, to: candidate) else { return nil }
            candidate = next
            guard candidate > threshold else { continue }
            if self == .weekdays && calendar.isDateInWeekend(candidate) { continue }
            if let minute = item.startMinuteOfDay,
               CalendarPlacement.start(on: candidate, minute: minute, calendar: calendar) == nil { continue }
            return candidate
        }
        return nil
    }
}

struct FreeTimeSlot: Identifiable, Equatable {
    let start: Date
    let end: Date
    var id: Date { start }
    var label: String { start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) + " · " + clockRange }
    var clockRange: String { Self.clock(start) + "–" + Self.clock(end) }
    static func clock(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return TodoItem.timeLabel((c.hour ?? 0) * 60 + (c.minute ?? 0))
    }
}

enum FreeTimePlanner {
    static func suggestions(for item: TodoItem, among items: [TodoItem], from firstDay: Date,
                            startMinute: Int, endMinute: Int, duration: Int, now: Date = .now,
                            calendar: Calendar = .current, limit: Int = 5) -> [FreeTimeSlot] {
        guard startMinute >= 0, endMinute <= 1440, startMinute < endMinute,
              (1...1440).contains(duration), limit > 0 else { return [] }
        let occupied = items.compactMap { other -> DateInterval? in
            guard other !== item, !other.isCompleted, let start = other.scheduledStart(calendar: calendar) else { return nil }
            return DateInterval(start: start, duration: Double(max(other.durationMinutes ?? 30, 1)) * 60)
        }
        var result: [FreeTimeSlot] = []
        var lastEnd = Date.distantPast
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: firstDay)),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: day) else { continue }
            let workEnd = endMinute == 1440 ? dayEnd : CalendarPlacement.start(on: day, minute: endMinute, calendar: calendar)
            guard let workEnd else { continue }
            for minute in stride(from: startMinute, to: endMinute, by: 15) {
                guard let start = CalendarPlacement.start(on: day, minute: minute, calendar: calendar), start > now, start >= lastEnd else { continue }
                let end = start.addingTimeInterval(Double(duration) * 60)
                guard end <= workEnd, !occupied.contains(where: { start < $0.end && $0.start < end }) else { continue }
                result.append(FreeTimeSlot(start: start, end: end))
                lastEnd = end
                if result.count == limit { return result }
            }
        }
        return result
    }
}

struct PlannedTaskMove: Identifiable {
    let item: TodoItem
    let originalStart: Date
    let start: Date
    var id: PersistentIdentifier { item.persistentModelID }
    var duration: Int { max(item.durationMinutes ?? 30, 1) }
    var end: Date { start.addingTimeInterval(Double(duration) * 60) }
}

enum SchedulePlanner {
    static func shifted(_ items: [TodoItem], ids: Set<PersistentIdentifier>, minutes: Int,
                        calendar: Calendar = .current) -> [PlannedTaskMove] {
        items.compactMap { item in
            guard ids.contains(item.persistentModelID), !item.isCompleted, !item.isFixedTime,
                  let original = item.scheduledStart(calendar: calendar) else { return nil }
            return PlannedTaskMove(item: item, originalStart: original, start: original.addingTimeInterval(Double(minutes) * 60))
        }.sorted { $0.originalStart < $1.originalStart }
    }

    static func conflicts(_ moves: [PlannedTaskMove], among items: [TodoItem], calendar: Calendar = .current) -> Set<PersistentIdentifier> {
        let destinations = Dictionary(uniqueKeysWithValues: moves.map { ($0.id, $0.start) })
        let active = items.filter { !$0.isCompleted }
        return Set(moves.filter { move in
            active.contains { other in
                guard other.persistentModelID != move.id,
                      let start = destinations[other.persistentModelID] ?? other.scheduledStart(calendar: calendar) else { return false }
                let end = start.addingTimeInterval(Double(max(other.durationMinutes ?? 30, 1)) * 60)
                return move.start < end && start < move.end
            }
        }.map(\.id))
    }

    static func isRepresentable(_ date: Date, calendar: Calendar = .current) -> Bool {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return CalendarPlacement.start(on: date, minute: (c.hour ?? 0) * 60 + (c.minute ?? 0), calendar: calendar) == date
    }

    @MainActor
    static func apply(_ moves: [PlannedTaskMove], in context: ModelContext, name: String,
                      protectFixed: Bool = true, calendar: Calendar = .current) throws {
        guard !moves.isEmpty else { throw PlanningError.noTasks }
        guard moves.allSatisfy({ !$0.item.isDeleted && !$0.item.isCompleted && (!$0.item.isFixedTime || !protectFixed)
            && $0.item.scheduledStart(calendar: calendar) == $0.originalStart
            && isRepresentable($0.start, calendar: calendar) }) else { throw PlanningError.changedPlan }
        let previous = moves.map { ($0.item, $0.item.dueDate, $0.item.startMinuteOfDay, $0.item.reminderIdentifier) }
        let undo = context.undoManager
        undo?.beginUndoGrouping()
        defer { undo?.endUndoGrouping() }
        for move in moves {
            let c = calendar.dateComponents([.hour, .minute], from: move.start)
            CalendarPlacement.move(move.item, to: move.start, minute: (c.hour ?? 0) * 60 + (c.minute ?? 0), calendar: calendar)
        }
        do {
            try context.save()
            undo?.setActionName(name)
        } catch {
            for (item, date, minute, reminder) in previous {
                item.dueDate = date; item.startMinuteOfDay = minute; item.reminderIdentifier = reminder
            }
            throw error
        }
    }
}

enum PlanningError: LocalizedError {
    case noTasks, changedPlan
    var errorDescription: String? {
        switch self {
        case .noTasks: "Select at least one task to move."
        case .changedPlan: "The plan changed, or a time is unavailable because the clocks change. Review the preview and try again."
        }
    }
}
