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
