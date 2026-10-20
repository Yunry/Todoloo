import AppKit
import Foundation
import SwiftData
import Testing
import UserNotifications
@testable import Todoloo

@MainActor
struct TodolooTests {
    private var today: Date { Calendar.current.startOfDay(for: .now) }
    private func day(_ offset: Int) -> Date { Calendar.current.date(byAdding: .day, value: offset, to: today)! }

    @Test func calendarWeeksRespectLocalFirstWeekdayAndYearBoundaries() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        calendar.firstWeekday = 2
        let date = try #require(calendar.date(from: DateComponents(year: 2027, month: 1, day: 1)))
        let week = CalendarScope.week.days(containing: date, calendar: calendar)
        #expect(week.count == 7)
        #expect(calendar.component(.weekday, from: week[0]) == 2)
        #expect(calendar.component(.year, from: week[0]) == 2026)
        #expect(week.contains { calendar.isDate($0, inSameDayAs: date) })
        #expect(CalendarScope.day.days(containing: date, calendar: calendar) == [date])
        calendar.firstWeekday = 1
        #expect(calendar.component(.weekday, from: CalendarScope.week.days(containing: date, calendar: calendar)[0]) == 1)
    }

    @Test func calendarDropSnapsAndClampsToQuarterHours() {
        #expect(CalendarPlacement.snappedMinute(-30) == 0)
        #expect(CalendarPlacement.snappedMinute(548) == 555)
        #expect(CalendarPlacement.snappedMinute(546) == 540)
        #expect(CalendarPlacement.snappedMinute(1440) == 1425)
        #expect(CalendarPlacement.snappedMinute(.infinity) == 0)
    }

    @Test func calendarMovePreservesEstimateAndReplacesReminderTime() throws {
        let task = TodoItem(title: "Move me", notes: "Keep these notes")
        task.dueDate = day(1)
        task.durationMinutes = 45
        task.setStartTime(540)
        let original = try #require(task.reminderPlan())
        #expect(CalendarPlacement.move(task, to: day(3), minute: 638))
        #expect(task.dueDate == day(3))
        #expect(task.startMinuteOfDay == 645)
        #expect(task.durationMinutes == 45)
        #expect(task.notes == "Keep these notes")
        let moved = try #require(task.reminderPlan())
        #expect(moved.id == original.id)
        #expect(moved.start != original.start)
        #expect(moved.start.timeIntervalSince(moved.fireDate) == 900)
        task.remindersEnabled = false
        #expect(CalendarPlacement.move(task, to: day(4), minute: 0))
        #expect(task.reminderPlan() == nil)
        task.setStartTime(nil)
        #expect(task.dueDate == day(4))
        #expect(task.durationMinutes == 45)
        #expect(task.reminderPlan() == nil)
    }

    @Test func calendarRejectsMissingClockTimeWithoutChangingTask() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        let spring = try #require(calendar.date(from: DateComponents(year: 2027, month: 3, day: 28)))
        let task = TodoItem(title: "Keep my plan")
        task.dueDate = spring.addingTimeInterval(-86400)
        task.setStartTime(540)
        let originalDate = task.dueDate
        let originalID = task.reminderIdentifier
        #expect(!CalendarPlacement.move(task, to: spring, minute: 135, calendar: calendar))
        #expect(task.dueDate == originalDate)
        #expect(task.startMinuteOfDay == 540)
        #expect(task.reminderIdentifier == originalID)
    }

    @Test func calendarLayoutKeepsOverlappingTasksVisibleAndReusesLanes() {
        func task(_ title: String, _ start: Int, _ duration: Int) -> TodoItem {
            let item = TodoItem(title: title)
            item.dueDate = today
            item.setStartTime(start)
            item.durationMinutes = duration
            return item
        }
        let first = task("First", 540, 60)
        let nested = task("Nested", 555, 15)
        let chained = task("Chained", 570, 60)
        let next = task("Next", 630, 30)
        let blocks = TaskCalendarLayout.blocks(for: today, items: [next, chained, nested, first])
        #expect(blocks.map(\.item.title) == ["First", "Nested", "Chained", "Next"])
        #expect(blocks.map(\.lane) == [0, 1, 1, 0])
        #expect(blocks.map(\.laneCount) == [2, 2, 2, 1])
        for left in blocks {
            for right in blocks where left.id != right.id && left.lane == right.lane {
                #expect(left.endMinute <= right.startMinute || right.endMinute <= left.startMinute)
            }
        }
    }

    @Test func calendarLayoutClipsOvernightTasksAndDoesNotInventEstimates() {
        let overnight = TodoItem(title: "Overnight")
        overnight.dueDate = day(-1)
        overnight.setStartTime(1425)
        overnight.durationMinutes = 60
        let unknown = TodoItem(title: "No estimate")
        unknown.dueDate = today
        unknown.setStartTime(540)
        let completed = TodoItem(title: "Done")
        completed.dueDate = today
        completed.setStartTime(600)
        completed.setCompleted(true)
        let blocks = TaskCalendarLayout.blocks(for: today, items: [overnight, unknown, completed])
        #expect(blocks.count == 2)
        #expect(blocks[0].startMinute == 0)
        #expect(blocks[0].endMinute == 45)
        #expect(blocks[0].continuesFromPreviousDay)
        #expect(blocks[1].endMinute - blocks[1].startMinute == 30)
        #expect(unknown.durationMinutes == nil)
        let previous = TaskCalendarLayout.blocks(for: day(-1), items: [overnight])
        #expect(previous.first?.endMinute == 1440)
        #expect(previous.first?.continuesToNextDay == true)
    }

    @Test func calendarMovePersistsAndCanBeUndoneAsOneAction() throws {
        let store = try ModelContainer(for: TodoItem.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = store.mainContext
        let undo = UndoManager()
        undo.groupsByEvent = false
        context.undoManager = undo
        undo.beginUndoGrouping()
        let task = TodoItem(title: "Original")
        task.dueDate = day(1)
        task.setStartTime(540)
        task.durationMinutes = 30
        context.insert(task)
        try context.save()
        undo.endUndoGrouping()
        undo.removeAllActions()
        undo.beginUndoGrouping()
        #expect(CalendarPlacement.move(task, to: day(2), minute: 615))
        context.processPendingChanges()
        try context.save()
        undo.endUndoGrouping()
        undo.undo()
        #expect(task.dueDate == day(1))
        #expect(task.startMinuteOfDay == 540)
        #expect(task.durationMinutes == 30)
        undo.redo()
        #expect(task.dueDate == day(2))
        #expect(task.startMinuteOfDay == 615)
    }

    @Test func dayPlanGroupsAndTotalsOnlyUnfinishedTasksForThatDay() {
        let early = TodoItem(title: "Early")
        early.dueDate = today
        early.setStartTime(540)
        early.durationMinutes = 30
        let late = TodoItem(title: "Late")
        late.dueDate = today
        late.setStartTime(600)
        late.durationMinutes = 60
        let flexible = TodoItem(title: "Flexible")
        flexible.dueDate = today
        let overdue = TodoItem(title: "Yesterday")
        overdue.dueDate = day(-1)
        overdue.durationMinutes = 120
        let finished = TodoItem(title: "Finished")
        finished.dueDate = today
        finished.durationMinutes = 45
        finished.setCompleted(true)
        let tomorrow = TodoItem(title: "Tomorrow")
        tomorrow.dueDate = day(1)
        let unscheduled = TodoItem(title: "Someday")
        let plan = DayPlan(items: [late, flexible, finished, tomorrow, overdue, unscheduled, early], date: today)
        #expect(plan.scheduled.map(\.title) == ["Early", "Late"])
        #expect(plan.overdue.map(\.title) == ["Yesterday"])
        #expect(plan.flexible.map(\.title) == ["Flexible"])
        #expect(plan.estimatedMinutes == 90)
        #expect(plan.missingEstimates == 1)
    }

    @Test func overlapsDetectNestedPlansButAllowConsecutiveTasks() {
        let long = TodoItem(title: "Long")
        long.dueDate = today
        long.setStartTime(540)
        long.durationMinutes = 120
        let nested = TodoItem(title: "Nested")
        nested.dueDate = today
        nested.setStartTime(555)
        nested.durationMinutes = 15
        let adjacent = TodoItem(title: "Adjacent")
        adjacent.dueDate = today
        adjacent.setStartTime(660)
        adjacent.durationMinutes = 30
        #expect(long.overlaps(nested))
        #expect(!long.overlaps(adjacent))
        #expect(!long.overlaps(long))
        let plan = DayPlan(items: [long, nested, adjacent], date: today)
        #expect(plan.overlappingIDs == Set([long.persistentModelID, nested.persistentModelID]))
        nested.setCompleted(true)
        #expect(!long.overlaps(nested))
        #expect(DayPlan(items: [long, nested, adjacent], date: today).overlappingIDs.isEmpty)
        nested.setCompleted(false)
        nested.durationMinutes = nil
        #expect(!long.overlaps(nested))
    }

    @Test func midnightFinishAndCrossDayConflict() {
        let late = TodoItem(title: "Late")
        late.dueDate = day(-1)
        late.setStartTime(1425)
        late.durationMinutes = 60
        let early = TodoItem(title: "Early")
        early.dueDate = today
        early.setStartTime(15)
        early.durationMinutes = 30
        #expect(late.plannedTimeLabel() == "23:45–00:45 (+1d)")
        #expect(late.overlaps(early))
        #expect(DayPlan(items: [late, early], date: today).overlappingIDs.contains(early.persistentModelID))
    }

    @Test func estimatesUseElapsedTimeAcrossDaylightSaving() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        let task = TodoItem(title: "Spring")
        task.dueDate = calendar.date(from: DateComponents(year: 2026, month: 3, day: 29))
        task.setStartTime(105)
        task.durationMinutes = 30
        #expect(task.plannedTimeLabel(calendar: calendar) == "01:45–03:15")
        #expect(task.plannedInterval(calendar: calendar)?.duration == 1800)
        task.setStartTime(135)
        #expect(task.plannedInterval(calendar: calendar) == nil)
        let plan = DayPlan(items: [task], date: try #require(task.dueDate), calendar: calendar)
        #expect(plan.flexible.count == 1)
        #expect(plan.scheduled.isEmpty)
    }

    @Test func appBundleContainsADecodableDockIcon() throws {
        let url = try #require(Bundle.main.url(forResource: "AppIcon", withExtension: "icns"))
        let icon = try #require(NSImage(contentsOf: url))
        #expect(icon.isValid)
        #expect(!icon.representations.isEmpty)
        #expect(Bundle.main.object(forInfoDictionaryKey: "CFBundleIconName") as? String == "AppIcon")
    }

    @Test func reminderMatchingDetectsReschedulesAndObsoleteTriggers() throws {
        let task = TodoItem(title: "Study")
        task.dueDate = day(1)
        task.setStartTime(540)
        let plan = try #require(task.reminderPlan())
        let original = plan.request()
        #expect(plan.matches(original))
        task.title = "Study chapter two"
        #expect(try #require(task.reminderPlan()).matches(original) == false)
        task.title = "Study"
        task.setStartTime(555)
        #expect(try #require(task.reminderPlan()).matches(original) == false)
        let obsolete = UNNotificationRequest(identifier: plan.id, content: original.content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false))
        #expect(!plan.matches(obsolete))
    }

    @Test func startTimeQuickEntryAndQuarterHourOptions() {
        #expect(TodoItem.startTimeOptions.count == 96)
        #expect(TodoItem.startTimeOptions.first == 0)
        #expect(TodoItem.startTimeOptions.last == 1425)
        for suffix in ["9:00", "09:15", "21:30", "23:45", "00:00"] {
            let parsed = TodoItem.parseDraft("Study (\(suffix)) (30mins)")
            #expect(parsed.title == "Study")
            #expect(parsed.startMinuteOfDay != nil)
            #expect(parsed.durationMinutes == 30)
        }
        let reversed = TodoItem.parseDraft("Study (1h 30m) (21:15)")
        #expect(reversed.title == "Study")
        #expect(reversed.startMinuteOfDay == 1275)
        #expect(reversed.durationMinutes == 90)
        for title in ["Study (24:00)", "Study (09:17)", "Study (9:60)", "Study (9:5)", "(09:15)"] {
            #expect(TodoItem.parseDraft(title).title == title)
            #expect(TodoItem.parseDraft(title).startMinuteOfDay == nil)
        }
    }

    @Test func remindersRespectDateAndMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 20)))
        let task = TodoItem(title: "Study")
        task.dueDate = date
        task.setStartTime(0)
        let plan = try #require(task.reminderPlan(now: date.addingTimeInterval(-3600), calendar: calendar))
        #expect(plan.start.timeIntervalSince(plan.fireDate) == 900)
        let fire = calendar.dateComponents([.day, .hour, .minute], from: plan.fireDate)
        #expect(fire.day == 19 && fire.hour == 23 && fire.minute == 45)
        let trigger = try #require(plan.request().trigger as? UNCalendarNotificationTrigger)
        #expect(trigger.dateComponents.calendar?.date(from: trigger.dateComponents) == plan.fireDate)
        #expect(!trigger.repeats)
        #expect(plan.request().content.sound != nil)
    }

    @Test func reschedulingCompletionAndReminderOptOut() throws {
        let task = TodoItem(title: "Study")
        task.dueDate = day(1)
        task.setStartTime(9 * 60)
        let original = try #require(task.reminderPlan())
        task.setStartTime(21 * 60 + 15)
        let moved = try #require(task.reminderPlan())
        #expect(moved.id == original.id)
        #expect(moved.fireDate > original.fireDate)
        task.title = "Read chapter two"
        #expect(task.reminderPlan()?.title == "Read chapter two")
        task.setCompleted(true)
        #expect(task.reminderPlan() == nil)
        task.setCompleted(false)
        #expect(task.reminderPlan() != nil)
        task.remindersEnabled = false
        #expect(task.reminderPlan() == nil)
        task.remindersEnabled = true
        task.setStartTime(nil)
        #expect(task.reminderPlan() == nil)
        task.setStartTime(540)
        task.dueDate = nil
        #expect(task.reminderPlan() == nil)
    }

    @Test func missedRemindersAreNotDeliveredLate() throws {
        let task = TodoItem(title: "Study")
        task.dueDate = day(1)
        task.setStartTime(540)
        let start = try #require(task.scheduledStart())
        #expect(task.reminderPlan(now: start.addingTimeInterval(-901)) != nil)
        #expect(task.reminderPlan(now: start.addingTimeInterval(-900)) == nil)
        #expect(task.reminderPlan(now: start.addingTimeInterval(-60)) == nil)
        #expect(task.reminderPlan(now: start.addingTimeInterval(60)) == nil)
    }

    @Test func daylightSavingTimeDoesNotMoveTasksToAnotherDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        let task = TodoItem(title: "Study")
        task.dueDate = try #require(calendar.date(from: DateComponents(year: 2027, month: 3, day: 28)))
        task.setStartTime(135) // 02:15 does not exist on this date in Berlin.
        #expect(task.scheduledStart(calendar: calendar) == nil)
        task.setStartTime(195)
        let start = try #require(task.scheduledStart(calendar: calendar))
        let plan = try #require(task.reminderPlan(now: .distantPast, calendar: calendar))
        #expect(calendar.isDate(start, inSameDayAs: try #require(task.dueDate)))
        #expect(start.timeIntervalSince(plan.fireDate) == 900)
    }

    @Test func autumnReminderUsesTheCorrectRepeatedHour() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        let task = TodoItem(title: "After the clock change")
        task.dueDate = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 25)))
        task.setStartTime(180)
        let plan = try #require(task.reminderPlan(now: .distantPast, calendar: calendar))
        let trigger = try #require(plan.request().trigger as? UNCalendarNotificationTrigger)
        let triggerDate = try #require(trigger.dateComponents.calendar?.date(from: trigger.dateComponents))
        #expect(triggerDate == plan.fireDate)
        #expect(plan.start.timeIntervalSince(triggerDate) == 900)
        #expect(calendar.dateComponents([.hour, .minute], from: triggerDate).hour == 2)
        #expect(calendar.timeZone.secondsFromGMT(for: triggerDate) == 3600)
    }

    @Test func dueDateSortUsesStartTimes() {
        let morning = TodoItem(title: "Morning")
        let evening = TodoItem(title: "Evening")
        morning.dueDate = day(1)
        evening.dueDate = day(1)
        morning.setStartTime(555)
        evening.setStartTime(1275)
        #expect(TaskSort.dueDate.ordered([evening, morning]).map(\.title) == ["Morning", "Evening"])
    }

    @Test func durationQuickEntry() {
        for suffix in ["30m", "30min", "30mins", "30 minutes", "30 MIN"] {
            let parsed = TodoItem.parseDraft("  Read a chapter (\(suffix))  ")
            #expect(parsed.title == "Read a chapter")
            #expect(parsed.durationMinutes == 30)
        }
        #expect(TodoItem.parseDraft("Plan (1h 30m)").durationMinutes == 90)
        #expect(TodoItem.parseDraft("Plan (2 hours)").durationMinutes == 120)
        for title in ["Plan (draft)", "Plan (0min)", "Plan (-30min)", "Plan (25h)", "Plan (99999999999999999999999min)", "(30min)", "Plan (30min) later"] {
            let parsed = TodoItem.parseDraft(title)
            #expect(parsed.title == title)
            #expect(parsed.durationMinutes == nil)
        }
    }

    @Test func durationFormattingAndRemoval() {
        let task = TodoItem(title: "Plan")
        #expect(task.durationLabel == nil)
        task.durationMinutes = 30
        #expect(task.durationLabel == "30 min")
        task.durationMinutes = 60
        #expect(task.durationLabel == "1 hr")
        task.durationMinutes = 90
        #expect(task.durationLabel == "1 hr 30 min")
        task.durationMinutes = nil
        #expect(task.durationLabel == nil)
    }

    @Test func dateFiltersAndOverdueBoundary() {
        let task = TodoItem(title: "Plan")
        #expect(!TodoFilter.today.includes(task, now: today))
        #expect(!TodoFilter.upcoming.includes(task, now: today))
        task.dueDate = day(-1)
        #expect(TodoFilter.today.includes(task, now: today))
        #expect(task.isOverdue(relativeTo: today))
        task.dueDate = today
        #expect(!task.isOverdue(relativeTo: today))
        #expect(TodoFilter.today.includes(task, now: today))
        task.dueDate = day(1)
        #expect(!TodoFilter.today.includes(task, now: today))
        #expect(TodoFilter.upcoming.includes(task, now: today))
        task.setCompleted(true)
        #expect(!TodoFilter.upcoming.includes(task, now: today))
    }

    @Test func completionAndListMembership() {
        let task = TodoItem(title: "Draft")
        task.dueDate = today
        task.listName = "Work"
        task.isImportant = true
        #expect(TodoFilter.work.includes(task))
        #expect(!TodoFilter.personal.includes(task))
        #expect(TodoFilter.important.includes(task))
        task.setCompleted(true)
        #expect(task.completedAt != nil)
        #expect(TodoFilter.completed.includes(task))
        #expect(TodoFilter.today.includes(task, now: today))
        task.dueDate = day(-1)
        #expect(!TodoFilter.today.includes(task, now: today))
        #expect(!task.isOverdue(relativeTo: today))
        task.setCompleted(false)
        #expect(task.completedAt == nil)
        #expect(!TodoFilter.completed.includes(task))
    }

    @Test func sortPlacesUnscheduledTasksLast() {
        let unscheduled = TodoItem(title: "Apple")
        let upcoming = TodoItem(title: "Zebra")
        upcoming.dueDate = day(1)
        upcoming.isImportant = true
        let overdue = TodoItem(title: "Middle")
        overdue.dueDate = day(-1)
        let tasks = [unscheduled, upcoming, overdue]
        #expect(TaskSort.dueDate.ordered(tasks).map(\.title) == ["Middle", "Zebra", "Apple"])
        #expect(TaskSort.title.ordered(tasks).map(\.title) == ["Apple", "Middle", "Zebra"])
        #expect(TaskSort.priority.ordered(tasks).first === upcoming)
    }

    @Test func persistenceRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = ModelConfiguration(url: directory.appendingPathComponent("tasks.store"))
        do {
            let store = try ModelContainer(for: TodoItem.self, configurations: configuration)
            let task = TodoItem(title: "A persistent task", notes: "Some context")
            task.listName = "Work"
            task.dueDate = today
            task.durationMinutes = 45
            task.setStartTime(1275)
            task.isImportant = true
            task.setCompleted(true)
            store.mainContext.insert(task)
            try store.mainContext.save()
        }
        let reopened = try ModelContainer(for: TodoItem.self, configurations: configuration)
        let tasks = try reopened.mainContext.fetch(FetchDescriptor<TodoItem>())
        #expect(tasks.count == 1)
        let task = try #require(tasks.first)
        #expect(task.title == "A persistent task")
        #expect(task.notes == "Some context")
        #expect(task.listName == "Work")
        #expect(task.dueDate == today)
        #expect(task.durationMinutes == 45)
        #expect(task.startMinuteOfDay == 1275)
        #expect(task.reminderIdentifier != nil)
        #expect(task.remindersEnabled)
        #expect(task.isImportant && task.isCompleted)
        #expect(task.completedAt != nil)
    }

    @Test func deletionCanBeUndone() throws {
        let store = try ModelContainer(for: TodoItem.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = store.mainContext
        let undo = UndoManager()
        undo.groupsByEvent = false
        context.undoManager = undo
        undo.beginUndoGrouping()
        let task = TodoItem(title: "Keep me")
        context.insert(task)
        try context.save()
        undo.endUndoGrouping()
        undo.removeAllActions()
        undo.beginUndoGrouping()
        context.delete(task)
        try context.save()
        undo.endUndoGrouping()
        #expect(try context.fetchCount(FetchDescriptor<TodoItem>()) == 0)
        undo.undo()
        #expect(try context.fetchCount(FetchDescriptor<TodoItem>()) == 1)
    }
}
