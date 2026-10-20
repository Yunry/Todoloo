import Foundation
import SwiftData

enum CalendarScope: String, CaseIterable, Identifiable {
    case day = "Day", week = "Week"
    var id: String { rawValue }

    func days(containing date: Date, calendar: Calendar = .current) -> [Date] {
        let start = self == .day ? calendar.startOfDay(for: date)
            : calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        return (0..<(self == .day ? 1 : 7)).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }
}

enum CalendarPlacement {
    static func snappedMinute(_ minute: Double) -> Int {
        guard minute.isFinite else { return 0 }
        return Int((min(max(minute, 0), 1425) / 15).rounded()) * 15
    }

    /// Validate before mutating so nonexistent spring-forward slots leave the original plan intact.
    @discardableResult
    static func move(_ item: TodoItem, to day: Date, minute: Int, calendar: Calendar = .current) -> Bool {
        let snapped = snappedMinute(Double(minute))
        let date = calendar.startOfDay(for: day)
        guard let start = calendar.date(bySettingHour: snapped / 60, minute: snapped % 60, second: 0,
                                       of: date, matchingPolicy: .strict, repeatedTimePolicy: .first),
              calendar.isDate(start, inSameDayAs: date) else { return false }
        item.dueDate = date
        item.setStartTime(snapped)
        return true
    }
}

struct CalendarBlock: Identifiable {
    let item: TodoItem
    let startMinute: Double
    let endMinute: Double
    let continuesFromPreviousDay: Bool
    let continuesToNextDay: Bool
    var lane: Int = 0
    var laneCount: Int = 1
    var id: PersistentIdentifier { item.persistentModelID }
}

enum TaskCalendarLayout {
    /// Missing estimates occupy a 30-minute visual placeholder without changing saved data.
    static func blocks(for day: Date, items: [TodoItem], calendar: Calendar = .current) -> [CalendarBlock] {
        guard let dayInterval = calendar.dateInterval(of: .day, for: day) else { return [] }
        func minute(_ date: Date) -> Double {
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            return Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
        }
        var blocks = items.compactMap { item -> CalendarBlock? in
            guard !item.isCompleted, let start = item.scheduledStart(calendar: calendar) else { return nil }
            let end = start.addingTimeInterval(Double(max(item.durationMinutes ?? 30, 1)) * 60)
            guard start < dayInterval.end, end > dayInterval.start else { return nil }
            let startMinute = start < dayInterval.start ? 0 : minute(start)
            let endMinute = end >= dayInterval.end ? 1440 : minute(end)
            return CalendarBlock(item: item, startMinute: startMinute,
                                 endMinute: min(1440, max(startMinute + 15, endMinute)),
                                 continuesFromPreviousDay: start < dayInterval.start,
                                 continuesToNextDay: end > dayInterval.end)
        }.sorted {
            if $0.startMinute != $1.startMinute { return $0.startMinute < $1.startMinute }
            if $0.endMinute != $1.endMinute { return $0.endMinute > $1.endMinute }
            return $0.item.createdAt < $1.item.createdAt
        }
        // Partition each connected overlap group into lanes so no task hides behind another.
        var groupStart = 0
        var groupEnd: Double = -1
        var laneEnds: [Double] = []
        func finishGroup(at end: Int) {
            for index in groupStart..<end { blocks[index].laneCount = max(laneEnds.count, 1) }
        }
        for index in blocks.indices {
            if blocks[index].startMinute >= groupEnd {
                finishGroup(at: index)
                groupStart = index
                laneEnds = []
            }
            let lane = laneEnds.firstIndex { $0 <= blocks[index].startMinute } ?? laneEnds.count
            if lane == laneEnds.count { laneEnds.append(blocks[index].endMinute) }
            else { laneEnds[lane] = blocks[index].endMinute }
            blocks[index].lane = lane
            groupEnd = max(laneEnds.max() ?? 0, blocks[index].endMinute)
        }
        finishGroup(at: blocks.count)
        return blocks
    }
}
