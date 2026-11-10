import SwiftData
import SwiftUI

struct FindTimeRequest: Identifiable {
    let id: PersistentIdentifier
}

struct FindTimeSheet: View {
    @Bindable var item: TodoItem
    @Query private var items: [TodoItem]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("workingDayStart") private var workStart = 540
    @AppStorage("workingDayEnd") private var workEnd = 1080
    @State private var firstDay = Calendar.current.startOfDay(for: Date.now)
    @State private var duration: Int
    @State private var selectedStart: Date?
    @State private var error: String?

    init(item: TodoItem) {
        self.item = item
        _duration = State(initialValue: max(item.durationMinutes ?? 30, 1))
    }

    private var slots: [FreeTimeSlot] {
        FreeTimePlanner.suggestions(for: item, among: items, from: firstDay,
                                    startMinute: workStart, endMinute: workEnd, duration: duration)
    }
    private var selectedSlot: FreeTimeSlot? { slots.first { $0.start == selectedStart } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Find a fit").font(.system(size: 27, design: .serif))
            Text(item.title).font(.system(size: 14, weight: .medium)).lineLimit(2)
            Text("Free time among your Todoloo tasks over the next seven days. Choose a slot to preview, then schedule it.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            HStack {
                DatePicker("Starting", selection: $firstDay, in: Calendar.current.startOfDay(for: Date.now)..., displayedComponents: .date)
                Spacer()
                TextField("Minutes", value: $duration, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder).frame(width: 65).accessibilityLabel("Find a fit duration")
                Text("min").foregroundStyle(.secondary)
            }
            HStack {
                Text("Working hours")
                Spacer()
                timePicker("Work starts", value: $workStart, options: Array(stride(from: 0, to: 1440, by: 15)))
                Text("to").foregroundStyle(.secondary)
                timePicker("Work ends", value: $workEnd, options: Array(stride(from: 15, through: 1440, by: 15)))
            }.font(.system(size: 12))
            ScrollView {
                VStack(spacing: 8) {
                    if slots.isEmpty {
                        Text(workStart >= workEnd ? "End working hours after the start time."
                             : !(1...1440).contains(duration) ? "Choose a duration from 1 to 1,440 minutes."
                             : "No free slots in these hours. Try a shorter duration, wider hours, or a later starting date.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 24)
                    }
                    ForEach(slots) { slot in
                        Button { selectedStart = slot.start } label: {
                            HStack {
                                Image(systemName: selectedStart == slot.start ? "largecircle.fill.circle" : "circle")
                                Text(slot.label).monospacedDigit()
                                Spacer()
                                Text(TodoItem.estimateLabel(duration)).foregroundStyle(.secondary)
                            }.font(.system(size: 12)).padding(12).contentShape(Rectangle())
                                .background(selectedStart == slot.start ? Palette.selection : Palette.sidebar,
                                            in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain).accessibilityLabel("Choose " + slot.label)
                    }
                }
            }.frame(height: 225)
            if let slot = selectedSlot {
                Label("Schedule \(slot.label) · \(TodoItem.estimateLabel(duration))", systemImage: "calendar.badge.checkmark")
                    .font(.system(size: 12)).foregroundStyle(Palette.green)
            }
            Text("A saved duration replaces the current estimate. Reminders follow your existing preference. Tasks without estimates reserve 30 minutes when checking availability.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            if let error { Text(error).font(.system(size: 11)).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Schedule task", action: schedule).keyboardShortcut(.defaultAction)
                    .disabled(selectedSlot == nil || item.isCompleted || item.isDeleted)
            }
        }.padding(26).frame(width: 520).background(Palette.background).foregroundStyle(Palette.ink)
        .onChange(of: duration) { _, _ in selectedStart = nil }
        .onChange(of: firstDay) { _, _ in selectedStart = nil }
        .onChange(of: workStart) { _, _ in selectedStart = nil }
        .onChange(of: workEnd) { _, _ in selectedStart = nil }
    }

    private func timePicker(_ title: String, value: Binding<Int>, options: [Int]) -> some View {
        Picker(title, selection: value) {
            ForEach(options, id: \.self) { Text(TodoItem.timeLabel($0)).tag($0) }
        }.labelsHidden().frame(width: 95).accessibilityLabel(title)
    }

    private func schedule() {
        guard let slot = selectedSlot, slot.start > .now, !item.isCompleted, !item.isDeleted else {
            error = "That slot is no longer available. Choose a new suggestion."; return
        }
        let old = (item.dueDate, item.startMinuteOfDay, item.durationMinutes, item.reminderIdentifier)
        context.undoManager?.beginUndoGrouping()
        defer { context.undoManager?.endUndoGrouping() }
        let clock = Calendar.current.dateComponents([.hour, .minute], from: slot.start)
        guard CalendarPlacement.move(item, to: slot.start, minute: (clock.hour ?? 0) * 60 + (clock.minute ?? 0)) else { return }
        item.durationMinutes = duration
        do {
            try context.save()
            context.undoManager?.setActionName("Find a fit")
            dismiss()
        } catch {
            item.dueDate = old.0; item.startMinuteOfDay = old.1; item.durationMinutes = old.2; item.reminderIdentifier = old.3
            self.error = error.localizedDescription
        }
    }
}

struct RunningLateSheet: View {
    @Query private var items: [TodoItem]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var day: Date
    @State private var minutes = 15
    @State private var selectedIDs = Set<PersistentIdentifier>()
    @State private var error: String?

    init(day: Date) { _day = State(initialValue: Calendar.current.startOfDay(for: day)) }
    private var timed: [TodoItem] {
        items.filter { !$0.isCompleted && $0.scheduledStart().map { Calendar.current.isDate($0, inSameDayAs: day) } == true }
            .sorted { ($0.startMinuteOfDay ?? 0) < ($1.startMinuteOfDay ?? 0) }
    }
    private var eligible: [TodoItem] { timed.filter { !$0.isFixedTime } }
    private var moves: [PlannedTaskMove] { SchedulePlanner.shifted(eligible, ids: selectedIDs, minutes: minutes) }
    private var conflicts: Set<PersistentIdentifier> { SchedulePlanner.conflicts(moves, among: items) }
    private var valid: Bool { !moves.isEmpty && moves.allSatisfy { SchedulePlanner.isRepresentable($0.start) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Running late?").font(.system(size: 27, design: .serif))
            Text("Choose the tasks to shift. Review their new times before applying the change.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            HStack {
                DatePicker("Day", selection: $day, displayedComponents: .date)
                Spacer()
                Picker("Delay", selection: $minutes) {
                    Text("15 min").tag(15); Text("30 min").tag(30); Text("1 hr").tag(60)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 205).accessibilityLabel("Delay")
            }
            HStack {
                Text("PREVIEW").font(.system(size: 10, weight: .semibold)).tracking(1)
                Spacer()
                Button("Select all") { selectedIDs = Set(eligible.map(\.persistentModelID)) }
                Button("Clear") { selectedIDs = [] }
            }.font(.system(size: 11))
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if timed.isEmpty {
                        Text("No unfinished timed tasks on this day.").foregroundStyle(.secondary).padding(.vertical, 20)
                    }
                    ForEach(timed) { item in previewRow(item) }
                }.font(.system(size: 12))
            }.frame(height: 245)
            Label("Fixed-time tasks stay in place. Mark them in task details using Fixed time.", systemImage: "lock")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            if !conflicts.isEmpty {
                Label("\(conflicts.count) shifted \(conflicts.count == 1 ? "task overlaps" : "tasks overlap") another plan. You can still apply this preview.",
                      systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11)).foregroundStyle(.orange)
            }
            if !moves.isEmpty && !valid {
                Text("A new time is ambiguous because the clocks change. Choose another delay or deselect that task.")
                    .font(.system(size: 11)).foregroundStyle(.red)
            }
            if let error { Text(error).font(.system(size: 11)).foregroundStyle(.red) }
            Text("Duration and checklist progress stay intact. Reminders update with the new start times. Undo the entire shift with ⌘Z.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Shift \(moves.count) \(moves.count == 1 ? "task" : "tasks")") {
                    do { try SchedulePlanner.apply(moves, in: context, name: "Shift tasks"); dismiss() }
                    catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction).disabled(!valid)
            }
        }.padding(26).frame(width: 550).background(Palette.background).foregroundStyle(Palette.ink)
        .onAppear { selectedIDs = Set(eligible.map(\.persistentModelID)) }
        .onChange(of: day) { _, _ in selectedIDs = Set(eligible.map(\.persistentModelID)) }
    }

    private func previewRow(_ item: TodoItem) -> some View {
        HStack(alignment: .top, spacing: 9) {
            if item.isFixedTime {
                Image(systemName: "lock.fill").foregroundStyle(.secondary).frame(width: 18)
            } else {
                Toggle(item.title, isOn: Binding(get: { selectedIDs.contains(item.persistentModelID) }, set: {
                    if $0 { selectedIDs.insert(item.persistentModelID) } else { selectedIDs.remove(item.persistentModelID) }
                })).labelsHidden().toggleStyle(.checkbox).accessibilityLabel("Shift " + item.title)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(item.title).fontWeight(.medium).lineLimit(2)
                if let move = moves.first(where: { $0.id == item.persistentModelID }) {
                    Text(FreeTimeSlot.clock(move.originalStart) + " → " + FreeTimeSlot.clock(move.start)
                         + (Calendar.current.isDate(move.start, inSameDayAs: day) ? "" : " · " + move.start.formatted(.dateTime.month(.abbreviated).day())))
                        .monospacedDigit().foregroundStyle(Palette.green)
                } else { Text((item.startTimeLabel ?? "") + (item.isFixedTime ? " · Fixed time" : " · Unchanged")).foregroundStyle(.secondary) }
            }
            Spacer()
            if conflicts.contains(item.persistentModelID) { Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange) }
        }.padding(10).background(Palette.sidebar, in: RoundedRectangle(cornerRadius: 8))
    }
}
