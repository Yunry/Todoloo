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

    @Test func nativeWindowUndoManagerReceivesListIconEdits() throws {
        let store = try TaskStore.make(inMemory: true)
        let context = store.mainContext
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 300, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let link = WindowUndoBridge.LinkView()
        link.modelContext = context
        window.contentView = link
        defer { window.contentView = nil }
        let undo = try #require(window.undoManager)
        #expect(context.undoManager === undo)
        undo.groupsByEvent = false
        let list = try ListCatalog.create("Native undo", icon: .travel, in: context)
        undo.removeAllActions()
        _ = try ListCatalog.rename("Native undo", to: "Native undo", icon: .study, in: context)
        #expect(list.symbolName == "graduationcap")
        undo.undo()
        #expect(list.symbolName == "airplane")
        undo.redo()
        #expect(list.symbolName == "graduationcap")
    }

    @Test func listIconsHaveNativeSymbolsAndSafeLegacyFallbacks() {
        #expect(ListIcon.allCases.count == 24)
        for icon in ListIcon.allCases {
            #expect(NSImage(systemSymbolName: icon.rawValue, accessibilityDescription: icon.label) != nil)
        }
        let legacy = TaskList(name: "Old list"); legacy.symbolName = nil
        #expect(ListCatalog.symbol(for: "Old list", lists: [legacy]) == "list.bullet")
        legacy.symbolName = "unknown-symbol"
        #expect(ListCatalog.symbol(for: "Old list", lists: [legacy]) == "list.bullet")
        #expect(ListCatalog.symbol(for: "Personal", lists: []) == "person")
        #expect(ListCatalog.symbol(for: "Work", lists: []) == "briefcase")
    }

    @Test func changingAnIconKeepsTasksAndSupportsUndoAndRename() throws {
        let store = try TaskStore.make(inMemory: true)
        let context = store.mainContext
        let undo = try #require(context.undoManager); undo.groupsByEvent = false
        let list = try ListCatalog.create("Travel", in: context)
        undo.beginUndoGrouping()
        let task = TodoItem(title: "Book train", notes: "Keep notes"); task.listName = "Travel"
        task.dueDate = day(1); task.setStartTime(540); task.durationMinutes = 30
        context.insert(task); try context.save(); undo.endUndoGrouping(); undo.removeAllActions()
        let reminder = task.reminderPlan()
        _ = try ListCatalog.rename("Travel", to: "Travel", icon: .travel, in: context)
        #expect(list.symbolName == "airplane" && task.listName == "Travel")
        #expect(task.reminderPlan() == reminder && task.notes == "Keep notes")
        undo.undo()
        #expect(list.symbolName == "list.bullet")
        undo.redo()
        #expect(list.symbolName == "airplane")
        _ = try ListCatalog.rename("Travel", to: "Journeys", in: context)
        #expect(list.symbolName == "airplane" && task.listName == "Journeys")
    }

    @Test func addingListStoragePreservesExistingTaskStoreAcrossRelaunches() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let taskURL = directory.appendingPathComponent("default.store")
        let listURL = directory.appendingPathComponent("lists.store")
        do {
            let original = try ModelContainer(for: TodoItem.self, configurations: ModelConfiguration(url: taskURL))
            let task = TodoItem(title: "Existing task", notes: "Keep me")
            task.setStartTime(540); task.dueDate = day(1)
            original.mainContext.insert(task); try original.mainContext.save()
        }
        do {
            let upgraded = try TaskStore.make(taskURL: taskURL, listURL: listURL)
            let tasks = try upgraded.mainContext.fetch(FetchDescriptor<TodoItem>())
            #expect(tasks.count == 1 && tasks.first?.notes == "Keep me")
            try ListCatalog.create("Empty list", icon: .travel, in: upgraded.mainContext)
        }
        for _ in 0..<2 {
            let reopened = try TaskStore.make(taskURL: taskURL, listURL: listURL)
            let tasks = try reopened.mainContext.fetch(FetchDescriptor<TodoItem>())
            let lists = try reopened.mainContext.fetch(FetchDescriptor<TaskList>())
            #expect(tasks.count == 1 && tasks.first?.title == "Existing task" && tasks.first?.startMinuteOfDay == 540)
            #expect(lists.count == 1 && lists.first?.name == "Empty list" && lists.first?.symbolName == "airplane")
        }
    }

    @Test func customListNamesValidateAndFiltersStayDistinct() throws {
        #expect(try ListCatalog.validatedName("  Travel  ", existing: ListCatalog.builtIn) == "Travel")
        for value in ["", "  ", "personal", " WORK ", String(repeating: "a", count: 61)] {
            do { _ = try ListCatalog.validatedName(value, existing: ListCatalog.builtIn); Issue.record("Invalid or duplicate name accepted") }
            catch { }
        }
        do { _ = try ListCatalog.validatedName("CAFE", existing: ["Café"]); Issue.record("Duplicate accepted") }
        catch { }
        let task = TodoItem(title: "Trip"); task.listName = "Travel"
        #expect(TodoFilter.list("Travel").includes(task))
        #expect(TodoFilter.list("Travel").listName == "Travel")
        #expect(!TodoFilter.work.includes(task) && !TodoFilter.personal.includes(task))
        #expect(TodoFilter.custom("Today").id != TodoFilter.today.id)
        let legacy = TodoItem(title: "Legacy"); legacy.listName = "Existing project"
        #expect(ListCatalog.names(lists: [TaskList(name: "Travel")], items: [task, legacy]) == ["Personal", "Work", "Existing project", "Travel"])
    }

    @Test func emptyCustomListsAndTaskAssignmentsPersistAcrossStoreReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = ModelConfiguration(url: directory.appendingPathComponent("custom-lists.store"))
        do {
            let store = try ModelContainer(for: TodoItem.self, TaskList.self, configurations: config)
            let context = store.mainContext
            try ListCatalog.create("Travel", in: context)
            try ListCatalog.create("Empty list", in: context)
            let task = TodoItem(title: "Book train"); task.listName = "Travel"
            context.insert(task); try context.save()
        }
        let reopened = try ModelContainer(for: TodoItem.self, TaskList.self, configurations: config)
        let names = try reopened.mainContext.fetch(FetchDescriptor<TaskList>()).map(\.name)
        #expect(Set(names) == ["Travel", "Empty list"])
        let items = try reopened.mainContext.fetch(FetchDescriptor<TodoItem>())
        #expect(items.count == 1 && items.first?.listName == "Travel")
    }

    @Test func renamingAndRemovingListsKeepTasksAndSupportUndo() throws {
        let store = try ModelContainer(for: TodoItem.self, TaskList.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = store.mainContext
        let undo = UndoManager(); undo.groupsByEvent = false; context.undoManager = undo
        try ListCatalog.create("Travel", in: context)
        undo.beginUndoGrouping()
        let active = TodoItem(title: "Book train", notes: "Keep notes"); active.listName = "Travel"
        active.dueDate = day(1); active.setStartTime(540); active.durationMinutes = 30; active.setRoutine(.daily)
        let finished = TodoItem(title: "Packed"); finished.listName = "Travel"; finished.setCompleted(true)
        context.insert(active); context.insert(finished); try context.save()
        undo.endUndoGrouping(); undo.removeAllActions()
        let reminder = active.reminderPlan()
        #expect(try ListCatalog.rename("Travel", to: "Trips", in: context) == "Trips")
        #expect(active.listName == "Trips" && finished.listName == "Trips")
        #expect(active.reminderPlan() == reminder && active.notes == "Keep notes" && active.routineRule == .daily)
        undo.undo()
        #expect(active.listName == "Travel" && finished.listName == "Travel")
        undo.redo()
        #expect(active.listName == "Trips")
        try ListCatalog.remove("Trips", in: context)
        #expect(active.listName == "Personal" && finished.listName == "Personal" && finished.isCompleted)
        #expect(try context.fetchCount(FetchDescriptor<TodoItem>()) == 2)
        #expect(try context.fetchCount(FetchDescriptor<TaskList>()) == 0)
        undo.undo()
        #expect(active.listName == "Trips" && finished.listName == "Trips")
        #expect(try context.fetchCount(FetchDescriptor<TaskList>()) == 1)
        do { try ListCatalog.remove("Personal", in: context); Issue.record("Default list removed") }
        catch { }
    }

    @Test func freeSlotsRespectBusyTimeWorkingHoursAndTheCurrentTime() throws {
        let task = TodoItem(title: "Find time")
        let busy = TodoItem(title: "Busy")
        busy.dueDate = day(1); busy.setStartTime(540); busy.durationMinutes = 60
        let finished = TodoItem(title: "Done")
        finished.dueDate = day(1); finished.setStartTime(600); finished.setCompleted(true)
        let slots = FreeTimePlanner.suggestions(for: task, among: [task, busy, finished], from: day(1),
                                               startMinute: 540, endMinute: 720, duration: 30, now: today, limit: 3)
        #expect(slots.count == 3)
        #expect(slots.map { Calendar.current.component(.hour, from: $0.start) } == [10, 10, 11])
        #expect(slots[0].end == slots[1].start)
        #expect(task.dueDate == nil && task.durationMinutes == nil)
        let later = FreeTimePlanner.suggestions(for: task, among: [], from: day(1), startMinute: 540,
                                               endMinute: 720, duration: 30, now: slots[0].start, limit: 1)
        #expect(try #require(later.first).start > slots[0].start)
        #expect(FreeTimePlanner.suggestions(for: task, among: [], from: today, startMinute: 720,
                                           endMinute: 540, duration: 30).isEmpty)
    }

    @Test func freeSlotsAccountForOvernightAndMissingEstimates() throws {
        let task = TodoItem(title: "Find")
        let overnight = TodoItem(title: "Overnight")
        overnight.dueDate = today; overnight.setStartTime(1425); overnight.durationMinutes = 60
        let placeholder = TodoItem(title: "No estimate")
        placeholder.dueDate = day(1); placeholder.setStartTime(45)
        let slots = FreeTimePlanner.suggestions(for: task, among: [overnight, placeholder], from: day(1),
                                               startMinute: 0, endMinute: 180, duration: 30, now: today, limit: 1)
        let clock = Calendar.current.dateComponents([.hour, .minute], from: try #require(slots.first).start)
        #expect(clock.hour == 1 && clock.minute == 15)
        #expect(placeholder.durationMinutes == nil)
    }

    @Test func shiftPreviewExcludesFixedAndCompletedTasksAndDetectsFinalConflicts() throws {
        let moving = TodoItem(title: "Moving"); moving.dueDate = day(1); moving.setStartTime(540); moving.durationMinutes = 30
        let fixed = TodoItem(title: "Fixed"); fixed.dueDate = day(1); fixed.setStartTime(570); fixed.isFixedTime = true
        let done = TodoItem(title: "Done"); done.dueDate = day(1); done.setStartTime(540); done.setCompleted(true)
        let items = [moving, fixed, done]
        let moves = SchedulePlanner.shifted(items, ids: Set(items.map(\.persistentModelID)), minutes: 30)
        #expect(moves.count == 1)
        #expect(moving.startMinuteOfDay == 540)
        #expect(SchedulePlanner.conflicts(moves, among: items) == [moving.persistentModelID])
        fixed.isFixedTime = false
        let together = SchedulePlanner.shifted(items, ids: Set(items.map(\.persistentModelID)), minutes: 30)
        #expect(together.count == 2)
        #expect(SchedulePlanner.conflicts(together, among: items).isEmpty)
    }

    @Test func scheduleShiftIsAtomicUndoableAndUpdatesRemindersAcrossMidnight() throws {
        let store = try ModelContainer(for: TodoItem.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = store.mainContext
        let undo = UndoManager(); undo.groupsByEvent = false; context.undoManager = undo
        undo.beginUndoGrouping()
        let task = TodoItem(title: "Late"); task.dueDate = day(1); task.setStartTime(1425); task.durationMinutes = 45
        task.addChecklistEntries("Keep progress"); task.updateChecklistEntry(try #require(task.checklist.first).id, completed: true)
        context.insert(task); try context.save(); undo.endUndoGrouping(); undo.removeAllActions()
        let previous = try #require(task.reminderPlan())
        let moves = SchedulePlanner.shifted([task], ids: [task.persistentModelID], minutes: 30)
        try SchedulePlanner.apply(moves, in: context, name: "Shift tasks")
        #expect(task.dueDate == day(2) && task.startMinuteOfDay == 15)
        #expect(task.durationMinutes == 45 && task.checklistProgress == "1/1 steps")
        #expect(task.reminderPlan()?.id == previous.id)
        #expect(task.reminderPlan()?.fireDate == previous.fireDate.addingTimeInterval(1800))
        undo.undo()
        #expect(task.dueDate == day(1) && task.startMinuteOfDay == 1425)
        undo.redo()
        #expect(task.dueDate == day(2) && task.startMinuteOfDay == 15)
        task.isFixedTime = true
        do { try SchedulePlanner.apply(moves, in: context, name: "Invalid"); Issue.record("A fixed or stale preview must be rejected") }
        catch { #expect(task.startMinuteOfDay == 15) }
    }

    @Test func gentleRoutinesSkipMissedOccurrencesAndPreserveTaskDetails() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 22)))
        let task = TodoItem(title: "Weekly", notes: "Keep notes")
        task.dueDate = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2))
        task.setStartTime(540); task.durationMinutes = 45; task.isFixedTime = true
        task.setRoutine(.weekly); task.addChecklistEntries("Step")
        task.updateChecklistEntry(try #require(task.checklist.first).id, completed: true)
        let id = task.reminderIdentifier
        #expect(task.advanceRoutine(completed: true, now: now, calendar: calendar))
        #expect(calendar.component(.day, from: try #require(task.dueDate)) == 23)
        #expect(!task.isCompleted && task.routineCompletionCount == 1 && task.lastRoutineCompletedAt == now)
        #expect(task.title == "Weekly" && task.notes == "Keep notes" && task.durationMinutes == 45)
        #expect(task.startMinuteOfDay == 540 && task.reminderIdentifier == id && task.isFixedTime)
        #expect(task.checklistProgress == "0/1 steps")
        #expect(task.advanceRoutine(completed: false, now: now, calendar: calendar))
        #expect(calendar.component(.day, from: try #require(task.dueDate)) == 30)
        #expect(task.routineCompletionCount == 1)
    }

    @Test func routineRulesHandleWeekendsEarlyCompletionAndDST() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        let friday = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 13)))
        let task = TodoItem(title: "Routine"); task.dueDate = friday; task.setRoutine(.weekdays)
        let monday = try #require(task.routineRule.nextDate(for: task, now: friday, calendar: calendar))
        #expect(calendar.component(.day, from: monday) == 16)
        task.dueDate = calendar.date(byAdding: .day, value: 10, to: friday)
        task.setRoutine(.afterDay)
        #expect(task.routineRule.nextDate(for: task, now: friday, calendar: calendar) == calendar.date(byAdding: .day, value: 1, to: friday))
        task.setRoutine(.daily); task.setStartTime(135)
        task.dueDate = calendar.date(from: DateComponents(year: 2027, month: 3, day: 27))
        let springDay = try #require(task.dueDate)
        let next = try #require(task.routineRule.nextDate(for: task, now: springDay, calendar: calendar))
        #expect(calendar.component(.day, from: next) == 29) // Skip nonexistent 02:15 on March 28.
        let repeated = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 2, minute: 15)))
        #expect(SchedulePlanner.isRepresentable(repeated, calendar: calendar))
        #expect(!SchedulePlanner.isRepresentable(repeated.addingTimeInterval(3600), calendar: calendar))
    }

    @Test func completingARoutineAdvancesAndCanBeUndone() throws {
        let store = try ModelContainer(for: TodoItem.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = store.mainContext
        let undo = UndoManager(); undo.groupsByEvent = false; context.undoManager = undo
        undo.beginUndoGrouping()
        let task = TodoItem(title: "Daily"); task.dueDate = today; task.setRoutine(.daily)
        context.insert(task); try context.save(); undo.endUndoGrouping(); undo.removeAllActions()
        undo.beginUndoGrouping(); task.setCompleted(true); try context.save(); undo.endUndoGrouping()
        #expect(task.dueDate == day(1) && !task.isCompleted && task.routineCompletionCount == 1)
        undo.undo()
        #expect(task.dueDate == today && task.routineCompletionCount == 0)
    }

    @Test func checklistsSupportEditingProgressSearchAndRemoval() throws {
        let task = TodoItem(title: "Prepare a trip")
        #expect(task.checklistProgress == nil)
        task.addChecklistEntries(" Book train \n\nPack charger\n")
        #expect(task.checklist.map(\.title) == ["Book train", "Pack charger"])
        let first = try #require(task.checklist.first)
        task.updateChecklistEntry(first.id, title: "Book the train", completed: true)
        #expect(task.checklistProgress == "1/2 steps")
        #expect(task.matchesSearch("CHARGER"))
        task.updateChecklistEntry(first.id, title: "  ")
        #expect(task.checklist[0].title == "Book the train")
        task.setCompleted(true)
        task.setCompleted(false)
        #expect(task.checklist[0].isCompleted)
        task.removeChecklistEntry(first.id)
        #expect(task.checklistProgress == "0/1 steps")
        task.removeChecklistEntry(try #require(task.checklist.first).id)
        #expect(task.checklistData == nil)
        #expect(!task.matchesSearch("charger"))
    }

    @Test func checklistChangesParticipateInUndo() throws {
        let store = try ModelContainer(for: TodoItem.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = store.mainContext
        context.undoManager = UndoManager()
        context.undoManager?.groupsByEvent = false
        context.undoManager?.beginUndoGrouping()
        let task = TodoItem(title: "Steps")
        task.addChecklistEntries("One\nTwo")
        context.insert(task)
        try context.save()
        context.undoManager?.endUndoGrouping()
        context.undoManager?.removeAllActions()
        let entry = try #require(task.checklist.first)
        context.undoManager?.beginUndoGrouping()
        task.updateChecklistEntry(entry.id, completed: true)
        try context.save()
        context.undoManager?.endUndoGrouping()
        #expect(task.checklistProgress == "1/2 steps")
        context.undoManager?.undo()
        #expect(task.checklistProgress == "0/2 steps")
        context.undoManager?.redo()
        #expect(task.checklistProgress == "1/2 steps")
    }

    @Test func quickEntryRecognizesRelativeDatesInAnyTokenOrder() {
        for draft in ["Read tomorrow (09:15) (30mins)", "Read (09:15) (tomorrow) (30mins)",
                      "Read (30mins) (09:15) TOMORROW"] {
            let parsed = TodoItem.parseDraft(draft)
            #expect(parsed.title == "Read")
            #expect(parsed.dateOffset == 1)
            #expect(parsed.startMinuteOfDay == 555)
            #expect(parsed.durationMinutes == 30)
        }
        #expect(TodoItem.parseDraft("Read today").dateOffset == 0)
        for title in ["Tomorrow", "Remember tomorrow morning", "Read (next week)"] {
            #expect(TodoItem.parseDraft(title).title == title)
            #expect(TodoItem.parseDraft(title).dateOffset == nil)
        }
    }

    @Test func calendarConflictPreviewIncludesOvernightAndPlaceholderBlocks() {
        let moving = TodoItem(title: "Moving")
        moving.durationMinutes = 30
        let overnight = TodoItem(title: "Overnight")
        overnight.dueDate = day(-1)
        overnight.setStartTime(1425)
        overnight.durationMinutes = 60
        let adjacent = TodoItem(title: "Adjacent")
        adjacent.dueDate = today
        adjacent.setStartTime(30)
        let done = TodoItem(title: "Finished")
        done.dueDate = today
        done.setStartTime(0)
        done.setCompleted(true)
        let tasks = [moving, overnight, adjacent, done]
        #expect(CalendarPlacement.conflicts(for: moving, on: today, minute: 0, among: tasks).map(\.title) == ["Overnight"])
        #expect(CalendarPlacement.conflicts(for: moving, on: today, minute: 45, among: tasks).map(\.title) == ["Adjacent"])
        #expect(CalendarPlacement.conflicts(for: moving, on: today, minute: 60, among: tasks).isEmpty)
        #expect(moving.dueDate == nil && moving.startMinuteOfDay == nil)
    }

    @Test func calendarMeasuredRegionsSurviveUnmeasuredSiblings() {
        let measured = CGRect(x: 0, y: 250, width: 800, height: 500)
        var viewport = CGRect.zero
        CalendarViewportKey.reduce(value: &viewport) { measured }
        CalendarViewportKey.reduce(value: &viewport) { .zero }
        #expect(viewport == measured)
        var visible = CGRect.zero
        CalendarVisibleFrameKey.reduce(value: &visible) { measured }
        CalendarVisibleFrameKey.reduce(value: &visible) { .zero }
        #expect(visible == measured)
        var tray = CGRect.zero
        CalendarTrayFrameKey.reduce(value: &tray) { measured }
        CalendarTrayFrameKey.reduce(value: &tray) { .zero }
        #expect(tray == measured)
        // A real resize must still replace the previous measurement.
        let resized = CGRect(x: 0, y: 250, width: 500, height: 400)
        CalendarViewportKey.reduce(value: &viewport) { resized }
        #expect(viewport == resized)
    }

    @Test func calendarDragPreservesGrabPointAndLeavesModelAloneUntilRelease() throws {
        let item = TodoItem(title: "Keep the original plan")
        item.dueDate = day(1)
        item.setStartTime(540)
        item.durationMinutes = 60
        let original = try #require(item.reminderPlan())
        let drag = CalendarDragState()
        drag.viewport = CGRect(x: 0, y: 100, width: 400, height: 600)
        drag.dayFrames = [day(1): CGRect(x: 0, y: -572, width: 200, height: 2016),
                          day(2): CGRect(x: 200, y: -572, width: 200, height: 2016)]
        // 09:00 is at y=184. Grab 30 minutes (42 points) into the task.
        drag.begin(item, at: CGPoint(x: 50, y: 226), day: day(1), startMinute: 540)
        #expect(drag.grabOffset == 42)
        #expect(drag.target == .time(day: day(1), minute: 540))
        drag.update(CGPoint(x: 250, y: 247))
        #expect(drag.target == .time(day: day(2), minute: 555))
        #expect(item.reminderPlan() == original)
        #expect(item.durationMinutes == 60)
        let result = try #require(drag.release())
        #expect(result.0 === item)
        #expect(result.1 == .time(day: day(2), minute: 555))
        #expect(!drag.isActive && drag.sourceID == nil)
    }

    @Test func escapeLatchesUntilMouseUpAndOutsideDropsCancel() {
        let item = TodoItem(title: "Unscheduled")
        let drag = CalendarDragState()
        drag.viewport = CGRect(x: 0, y: 100, width: 200, height: 600)
        drag.dayFrames = [today: CGRect(x: 0, y: 100, width: 200, height: 2016)]
        drag.begin(item, at: CGPoint(x: 50, y: 150))
        drag.cancel()
        drag.begin(item, at: CGPoint(x: 50, y: 200))
        drag.update(CGPoint(x: 50, y: 210))
        #expect(drag.target == nil && !drag.isActive)
        #expect(drag.release() == nil)
        #expect(item.dueDate == nil && item.startMinuteOfDay == nil && item.reminderIdentifier == nil)
        drag.begin(item, at: CGPoint(x: 50, y: 150))
        drag.update(CGPoint(x: 300, y: 210))
        #expect(drag.release() == nil)
        // A horizontally clipped day behind the inspector isn't a drop destination.
        drag.visibleFrame = CGRect(x: 0, y: 100, width: 100, height: 600)
        drag.begin(item, at: CGPoint(x: 50, y: 150))
        drag.update(CGPoint(x: 150, y: 210))
        #expect(drag.release() == nil)
    }

    @Test func calendarDragRecalculatesAfterScrollAndRecognizesFlexibleTray() {
        let item = TodoItem(title: "Move")
        let drag = CalendarDragState()
        drag.viewport = CGRect(x: 0, y: 100, width: 200, height: 600)
        drag.tray = CGRect(x: 0, y: 0, width: 200, height: 80)
        drag.dayFrames = [today: CGRect(x: 0, y: 100, width: 200, height: 2016)]
        drag.begin(item, at: CGPoint(x: 50, y: 150), day: today, startMinute: 30)
        let offset = drag.grabOffset
        drag.update(CGPoint(x: 50, y: 690))
        #expect(drag.edgeScrollDirection == 1)
        let before = drag.target
        drag.dayFrames = [today: CGRect(x: 0, y: 79, width: 200, height: 2016)]
        #expect(drag.target != before)
        #expect(drag.grabOffset == offset)
        drag.update(CGPoint(x: 50, y: 110))
        #expect(drag.edgeScrollDirection == -1)
        drag.update(CGPoint(x: 50, y: 40))
        #expect(drag.target == .flexible)
        #expect(drag.edgeScrollDirection == 0)
        drag.finish()
    }

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
            task.isFixedTime = true
            task.setRoutine(.weekly)
            task.routineCompletionCount = 3
            task.lastRoutineCompletedAt = today
            task.addChecklistEntries("First step\nSecond step")
            task.updateChecklistEntry(try #require(task.checklist.first).id, completed: true)
            task.setRoutine(.none)
            task.setCompleted(true)
            task.setRoutine(.weekly)
            store.mainContext.insert(task)
            try store.mainContext.save()
        }
        let reopened = try ModelContainer(for: TodoItem.self, configurations: configuration)
        let tasks = try reopened.mainContext.fetch(FetchDescriptor<TodoItem>())
        #expect(tasks.count == 1)
        let task = try #require(tasks.first)
        #expect(task.title == "A persistent task")
        #expect(task.isFixedTime && task.routineRule == .weekly && task.routineCompletionCount == 3)
        #expect(task.lastRoutineCompletedAt == today)
        #expect(task.checklistProgress == "1/2 steps")
        #expect(task.checklist.map(\.title) == ["First step", "Second step"])
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
