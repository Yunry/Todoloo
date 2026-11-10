import AppKit
import SwiftData
import SwiftUI
import UserNotifications

struct TodoInspectorView: View {
    let itemID: PersistentIdentifier?
    @Query private var items: [TodoItem]

    var body: some View {
        Group {
            if let item = items.first(where: { $0.persistentModelID == itemID }) {
                TaskDetailsForm(item: item, otherItems: items).id(item.persistentModelID)
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "text.alignleft").font(.system(size: 28, weight: .ultraLight))
                    Text("A closer look").font(.system(size: 22, design: .serif))
                    Text("Choose a task to add notes,\nset a date, or make it a priority.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .foregroundStyle(Palette.green).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Palette.background)
    }
}

private struct TaskDetailsForm: View {
    @Bindable var item: TodoItem
    let otherItems: [TodoItem]
    @Environment(\.modelContext) private var modelContext
    @State private var saveError: String?
    @State private var checklistDraft = ""
    @Query private var lists: [TaskList]
    @EnvironmentObject private var reminders: ReminderScheduler

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("TASK DETAILS").font(.system(size: 10, weight: .semibold)).tracking(1.5).foregroundStyle(.secondary)
                TextField("Task title", text: titleBinding, axis: .vertical)
                    .font(.system(size: 22, weight: .regular, design: .serif))
                    .textFieldStyle(.plain).lineLimit(1...8).foregroundStyle(Palette.ink)
                    .accessibilityLabel("Task title")
                Toggle(item.routineRule != .none && !item.isCompleted ? "Complete occurrence" : "Completed", isOn: Binding(get: { item.isCompleted }, set: { item.setCompleted($0) }))
                    .toggleStyle(.checkbox)
                if !item.isCompleted {
                    Button("Find a fit…") { NotificationCenter.default.post(name: .findTimeForTask, object: item.persistentModelID) }
                        .buttonStyle(.bordered).controlSize(.small)
                }
                Divider()
                routineControls
                Divider()
                VStack(alignment: .leading, spacing: 16) {
                    Picker(selection: $item.listName) {
                        ForEach(ListCatalog.names(lists: lists, items: otherItems), id: \.self) { name in
                            Label(name, systemImage: ListCatalog.symbol(for: name, lists: lists)).tag(name)
                        }
                    } label: { Label("List", systemImage: "tray") }
                    Toggle(isOn: $item.isImportant) { Label("Important", systemImage: "flag") }
                        .toggleStyle(.switch).controlSize(.small)
                    Toggle(isOn: Binding(get: { item.dueDate != nil }, set: {
                        item.dueDate = $0 ? Calendar.current.startOfDay(for: .now) : nil
                        if !$0 { item.setStartTime(nil) }
                    })) {
                        Label("Due date", systemImage: "calendar")
                    }.toggleStyle(.switch).controlSize(.small)
                    if item.dueDate != nil {
                        DatePicker("Due", selection: Binding(get: { item.dueDate ?? .now }, set: { item.dueDate = $0 }), displayedComponents: .date)
                            .labelsHidden().datePickerStyle(.field).accessibilityLabel("Due date")
                        HStack {
                            Button("Today") { item.dueDate = Calendar.current.startOfDay(for: .now) }
                            Button("Tomorrow") { item.dueDate = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)) }
                        }.buttonStyle(.bordered).controlSize(.small)
                    }
                    Toggle(isOn: Binding(get: { item.startMinuteOfDay != nil }, set: {
                        let clock = Calendar.current.dateComponents([.hour, .minute], from: .now)
                        let nextSlot = min(((clock.hour ?? 0) * 60 + (clock.minute ?? 0) + 29) / 15 * 15, 1425)
                        item.setStartTime($0 ? nextSlot : nil)
                    })) {
                        Label("Start time", systemImage: "clock.badge")
                    }.toggleStyle(.switch).controlSize(.small)
                    if item.startMinuteOfDay != nil {
                        Toggle(isOn: $item.isFixedTime) { Label("Fixed time", systemImage: "lock") }
                            .toggleStyle(.checkbox)
                            .help("Running late keeps this task in place. You can still reschedule it manually.")
                        HStack(spacing: 5) {
                            Text("Start at")
                            Spacer()
                            Picker("Hour", selection: Binding(get: { (item.startMinuteOfDay ?? 540) / 60 }, set: {
                                item.setStartTime($0 * 60 + (item.startMinuteOfDay ?? 0) % 60)
                            })) {
                                ForEach(0..<24) { Text(String(format: "%02d", $0)).tag($0) }
                            }.labelsHidden().frame(width: 65).accessibilityLabel("Start hour, 24-hour clock")
                            Text(":").foregroundStyle(.secondary)
                            Picker("Minute", selection: Binding(get: { (item.startMinuteOfDay ?? 540) % 60 }, set: {
                                item.setStartTime((item.startMinuteOfDay ?? 540) / 60 * 60 + $0)
                            })) {
                                ForEach([0, 15, 30, 45], id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                            }.labelsHidden().frame(width: 65).accessibilityLabel("Start minute, 15-minute steps")
                        }
                        Toggle(isOn: $item.remindersEnabled) {
                            Label("Remind me 15 min before", systemImage: "bell")
                        }.toggleStyle(.checkbox)
                        if item.remindersEnabled {
                            TimelineView(.periodic(from: .now, by: 60)) { context in
                                reminderStatus(now: context.date)
                            }
                        }
                    }
                    Toggle(isOn: Binding(get: { item.durationMinutes != nil }, set: { item.durationMinutes = $0 ? 30 : nil })) {
                        Label("Estimated time", systemImage: "clock")
                    }.toggleStyle(.switch).controlSize(.small)
                    if item.durationMinutes != nil {
                        HStack(spacing: 8) {
                            TextField("Minutes", value: durationBinding, format: .number.grouping(.never))
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 60)
                                .accessibilityLabel("Estimated minutes")
                            Text("minutes").foregroundStyle(.secondary)
                            Spacer()
                            Stepper("Estimated minutes", value: durationBinding, in: 1...1440, step: 5)
                                .labelsHidden().accessibilityLabel("Adjust estimated minutes")
                        }
                        HStack(spacing: 6) {
                            ForEach([15, 30, 60], id: \.self) { minutes in
                                Button(minutes == 60 ? "1 hr" : "\(minutes) min") {
                                    item.durationMinutes = minutes
                                }
                                .tint(item.durationMinutes == minutes ? Palette.green : .secondary)
                            }
                        }.buttonStyle(.bordered).controlSize(.small)
                    }
                    if let interval = item.plannedInterval() {
                        let finishDay = Calendar.current.isDate(interval.start, inSameDayAs: interval.end)
                            ? "" : " · \(interval.end.formatted(.dateTime.month(.abbreviated).day()))"
                        let endClock = Calendar.current.dateComponents([.hour, .minute], from: interval.end)
                        Label("Estimated finish: \(TodoItem.timeLabel((endClock.hour ?? 0) * 60 + (endClock.minute ?? 0)))\(finishDay)",
                              systemImage: "flag.checkered")
                            .foregroundStyle(.secondary)
                        let conflicts = otherItems.filter { item.overlaps($0) }
                        if !conflicts.isEmpty {
                            VStack(alignment: .leading, spacing: 5) {
                                Label("Overlapping plans", systemImage: "exclamationmark.triangle")
                                    .fontWeight(.medium)
                                ForEach(conflicts) { other in
                                    Text("\(other.title) · \(other.plannedTimeLabel() ?? "")")
                                }
                                Text("Adjust a start time or estimate to leave room.")
                                    .foregroundStyle(.secondary)
                            }
                            .font(.system(size: 11))
                            .padding(10)
                            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                            .accessibilityElement(children: .combine)
                        }
                    }
                }.font(.system(size: 12))
                Divider()
                checklistSection
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Label("NOTES", systemImage: "text.alignleft")
                        .font(.system(size: 10, weight: .semibold)).tracking(1.2).foregroundStyle(.secondary)
                    TextField("A thought, a link, a little context…", text: $item.notes, axis: .vertical)
                        .font(.system(size: 13)).textFieldStyle(.plain).lineLimit(6...20)
                        .padding(12).background(Palette.sidebar.opacity(0.65), in: RoundedRectangle(cornerRadius: 9))
                        .accessibilityLabel("Task notes")
                }
                Spacer(minLength: 10)
                Text("Created \(item.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                if let completedAt = item.completedAt {
                    Text("Completed \(completedAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                Button(role: .destructive) {
                    NSApp.keyWindow?.makeFirstResponder(nil)
                    modelContext.delete(item)
                    do { try modelContext.save() } catch { saveError = error.localizedDescription }
                } label: { Label("Delete task", systemImage: "trash") }
                    .buttonStyle(.borderless).font(.system(size: 12))
                    .help("Delete task. Use Edit → Undo to restore it.")
            }.padding(24)
        }
        .alert("Couldn’t save your changes", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: { Text(saveError ?? "") }
    }
    private var routineControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Repeat", selection: Binding(get: { item.routineRule }, set: { item.setRoutine($0) })) {
                ForEach(RoutineRule.allCases) { Text($0.label).tag($0) }
            }.font(.system(size: 12))
            if item.routineRule != .none {
                Text("Completing or skipping advances this one task to its next date. Checklist steps reset for the new occurrence.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                if let date = item.routineRule.nextDate(for: item, now: .now, calendar: .current) {
                    Text("After completion: " + date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                        .font(.system(size: 11)).foregroundStyle(Palette.green)
                }
                if !item.isCompleted {
                    Button("Skip once") { item.advanceRoutine(completed: false) }.controlSize(.small)
                }
                if item.routineCompletionCount > 0 {
                    Text("\(item.routineCompletionCount) \(item.routineCompletionCount == 1 ? "occurrence" : "occurrences") completed")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                if item.isCompleted { Text("Reopen this task to resume its routine.").font(.system(size: 11)).foregroundStyle(.secondary) }
            }
        }
    }

    private var checklistSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("CHECKLIST", systemImage: "checklist")
                    .font(.system(size: 10, weight: .semibold)).tracking(1.2)
                Spacer()
                if let progress = item.checklistProgress {
                    Text(progress).font(.system(size: 10)).monospacedDigit()
                }
            }.foregroundStyle(.secondary)
            ForEach(item.checklist) { entry in
                HStack(alignment: .top, spacing: 7) {
                    Toggle(entry.title, isOn: Binding(get: {
                        item.checklist.first { $0.id == entry.id }?.isCompleted ?? false
                    }, set: { item.updateChecklistEntry(entry.id, completed: $0) }))
                        .labelsHidden().toggleStyle(.checkbox).accessibilityLabel("Complete step: \(entry.title)")
                    TextField("Step", text: Binding(get: {
                        item.checklist.first { $0.id == entry.id }?.title ?? ""
                    }, set: { item.updateChecklistEntry(entry.id, title: $0) }), axis: .vertical)
                        .textFieldStyle(.plain).font(.system(size: 12)).lineLimit(1...4)
                        .strikethrough(entry.isCompleted).foregroundStyle(entry.isCompleted ? .secondary : Palette.ink)
                        .accessibilityLabel("Checklist step")
                    Button { item.removeChecklistEntry(entry.id) } label: {
                        Image(systemName: "xmark").font(.system(size: 9))
                    }.buttonStyle(.plain).foregroundStyle(.secondary)
                        .help("Remove step").accessibilityLabel("Remove step: \(entry.title)")
                }.padding(.vertical, 3)
            }
            HStack(spacing: 6) {
                TextField("Add a step…", text: $checklistDraft)
                    .textFieldStyle(.plain).font(.system(size: 12))
                    .onSubmit(addChecklistEntries).accessibilityLabel("New checklist step")
                Button(action: addChecklistEntries) { Image(systemName: "plus.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(Palette.green).accessibilityLabel("Add checklist step")
                    .disabled(checklistDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding(9).background(Palette.sidebar, in: RoundedRectangle(cornerRadius: 7))
        }
    }

    private func addChecklistEntries() {
        item.addChecklistEntries(checklistDraft)
        checklistDraft = ""
    }

    private var titleBinding: Binding<String> {
        Binding(get: { item.title }, set: { value in
            if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { item.title = value }
        })
    }

    private var durationBinding: Binding<Int> {
        Binding(get: { item.durationMinutes ?? 30 }, set: { item.durationMinutes = min(max($0, 1), 1440) })
    }

    @ViewBuilder
    private func reminderStatus(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if reminders.isPreview {
                Text("Reminders are off in this temporary demo.")
            } else if let error = reminders.errorMessage {
                Text(error).foregroundStyle(.red)
            } else if reminders.authorization == .denied || (reminders.authorization == .authorized && !reminders.bannersEnabled) {
                Text("Allow Todoloo notifications and banners in System Settings to see reminders.")
                Button("Notification settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
                }.buttonStyle(.link)
            } else if item.isCompleted {
                Text("Reminder canceled — task completed.")
            } else if let start = item.scheduledStart() {
                let fire = start.addingTimeInterval(-15 * 60)
                if fire <= now {
                    Text("The 15-minute reminder time has passed. Choose a later start for a reminder.")
                } else if let id = item.reminderIdentifier, reminders.scheduledIDs.contains("todoloo.task." + id) {
                    Text("Reminder set for \(fire.formatted(date: .abbreviated, time: .shortened)).")
                } else {
                    Text("Waiting to schedule. Allow notifications when macOS asks.")
                }
            } else {
                Text("This time doesn’t occur on this date. Choose another time.")
            }
            if !reminders.isPreview && reminders.authorization == .authorized && reminders.bannersEnabled {
                Button("Test reminder") { Task { await reminders.sendTestReminder() } }
                    .buttonStyle(.link)
                if let status = reminders.testStatus { Text(status) }
            }
        }.font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}
