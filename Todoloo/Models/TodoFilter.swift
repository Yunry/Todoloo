import SwiftUI

enum TodoFilter: String, CaseIterable, Identifiable, Hashable {
    case today, calendar, upcoming, all, important, completed, personal, work
    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: "Today"
        case .calendar: "Calendar"
        case .upcoming: "Upcoming"
        case .all: "All tasks"
        case .important: "Important"
        case .completed: "Completed"
        case .personal: "Personal"
        case .work: "Work"
        }
    }
    var systemImage: String {
        switch self {
        case .today: "sun.max"
        case .calendar: "calendar.day.timeline.left"
        case .upcoming: "calendar"
        case .all: "tray"
        case .important: "flag"
        case .completed: "checkmark.circle"
        case .personal: "person"
        case .work: "briefcase"
        }
    }
    var subtitle: String {
        switch self {
        case .today: "A little focus. A lighter day."
        case .calendar: "Make room for what matters."
        case .upcoming: "Give tomorrow a little breathing room."
        case .all: "Everything on your mind, in one place."
        case .important: "Make space for what matters most."
        case .completed: "Small steps. Real progress."
        case .personal: "A little space for your everyday life."
        case .work: "Good work starts with a clear head."
        }
    }
    func includes(_ item: TodoItem, now: Date = .now) -> Bool {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        switch self {
        case .today:
            guard let due = item.dueDate else { return false }
            return due < tomorrow && (!item.isCompleted || calendar.isDate(due, inSameDayAs: now))
        case .upcoming:
            guard let due = item.dueDate else { return false }
            return !item.isCompleted && due >= tomorrow
        case .all: return true
        case .calendar: return !item.isCompleted
        case .important: return item.isImportant
        case .completed: return item.isCompleted
        case .personal: return item.listName == "Personal"
        case .work: return item.listName == "Work"
        }
    }
}

enum TaskSort: String, CaseIterable, Identifiable {
    case newest = "Newest first", dueDate = "Due date", priority = "Priority", title = "Title"
    var id: String { rawValue }
    func ordered(_ items: [TodoItem]) -> [TodoItem] {
        if self == .dueDate {
            // Resolve calendar/DST dates once per task, rather than during every sort comparison.
            let datedItems: [(item: TodoItem, date: Date)] = items.map { item in
                let date = item.scheduledStart() ?? item.dueDate ?? Date.distantFuture
                return (item: item, date: date)
            }
            let ordered = datedItems.sorted { lhs, rhs in
                if lhs.date == rhs.date { return lhs.item.createdAt > rhs.item.createdAt }
                return lhs.date < rhs.date
            }
            return ordered.map { $0.item }
        }
        return items.sorted { lhs, rhs in
            switch self {
            case .newest, .dueDate: break
            case .priority:
                if lhs.isImportant != rhs.isImportant { return lhs.isImportant }
            case .title:
                let result = lhs.title.localizedStandardCompare(rhs.title)
                if result != .orderedSame { return result == .orderedAscending }
            }
            return lhs.createdAt > rhs.createdAt
        }
    }
}
