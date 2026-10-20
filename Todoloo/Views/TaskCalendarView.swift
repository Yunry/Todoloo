import AppKit
import SwiftData
import SwiftUI

struct TaskCalendarView: View {
    @Binding var selectedItemID: PersistentIdentifier?
    @Binding var showingInspector: Bool
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TodoItem.createdAt) private var items: [TodoItem]
    @AppStorage("calendarScope") private var scope: CalendarScope = .week
    @State private var date = Calendar.current.startOfDay(for: Date.now)
    @State private var search = ""
    @State private var editor: CalendarEditRequest?
    @State private var error: String?
    @State private var feedback = "Drag tasks to plan your time. Double-click an empty slot to add one."
    @State private var showingFlexible = true
    @State private var scrollHour: Int? = 8
    @FocusState private var searchFocused: Bool

    private let hourHeight: CGFloat = 84
    private let gutter: CGFloat = 52
    private var days: [Date] { scope.days(containing: date) }
    private var visibleItems: [TodoItem] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter {
            !$0.isCompleted && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)
                               || $0.notes.localizedCaseInsensitiveContains(query))
        }
    }
    private var flexible: [TodoItem] { visibleItems.filter { $0.scheduledStart() == nil } }

    var body: some View {
        VStack(spacing: 0) {
            header
            flexibleTray
            Divider().opacity(0.5)
            GeometryReader { geometry in
                let width = max(geometry.size.width, gutter + CGFloat(days.count) * 100)
                let columnWidth = (width - gutter) / CGFloat(days.count)
                ScrollView(.horizontal) {
                    VStack(spacing: 0) {
                        dayHeaders(columnWidth: columnWidth)
                        ScrollViewReader { proxy in
                            ScrollView(.vertical) {
                                HStack(alignment: .top, spacing: 0) {
                                    timeRuler
                                    ForEach(days, id: \.self) { day in
                                        CalendarDayColumn(
                                            day: day, width: columnWidth, hourHeight: hourHeight,
                                            blocks: TaskCalendarLayout.blocks(for: day, items: visibleItems),
                                            selectedItemID: selectedItemID,
                                            open: openDetails,
                                            edit: { item in editor = CalendarEditRequest(item: item) },
                                            create: { minute in editor = CalendarEditRequest(date: day, minute: minute) },
                                            drop: { tokens, minute in move(tokens, to: day, minute: minute) },
                                            makeFlexible: makeFlexible
                                        )
                                    }
                                }
                                .frame(width: width, height: hourHeight * 24)
                            }
                            .scrollPosition(id: $scrollHour, anchor: .top)
                            .onAppear { proxy.scrollTo(8, anchor: .top) }
                        }
                    }
                    .frame(width: width, height: geometry.size.height)
                }
            }
            HStack(spacing: 7) {
                Image(systemName: "hand.draw").foregroundStyle(Palette.green)
                Text(feedback).lineLimit(2)
                Spacer(minLength: 0)
            }
            .font(.system(size: 11)).foregroundStyle(.secondary)
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background(Palette.sidebar.opacity(0.45))
            .accessibilityElement(children: .combine)
        }
        .background(Palette.background)
        .sheet(item: $editor) { request in
            CalendarTaskEditor(request: request) { title, day, minute, duration in
                saveEditor(request, title: title, day: day, minute: minute, duration: duration)
            }
        }
        .alert("Couldn’t update the plan", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
        .onReceive(NotificationCenter.default.publisher(for: .focusNewTodoField)) { _ in
            editor = CalendarEditRequest(date: date, minute: 540)
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearchField)) { _ in searchFocused = true }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Calendar").font(.system(size: 30, design: .serif)).foregroundStyle(Palette.ink)
                Spacer()
                Picker("Calendar view", selection: $scope) {
                    ForEach(CalendarScope.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().frame(width: 140)
                Button {
                    editor = CalendarEditRequest(date: date, minute: 540)
                } label: { Image(systemName: "plus") }
                    .help("New calendar task (⌘N)").accessibilityLabel("New calendar task")
            }
            HStack(spacing: 8) {
                Button { navigate(-1) } label: { Image(systemName: "chevron.left") }
                    .help(scope == .week ? "Previous week" : "Previous day")
                    .accessibilityLabel(scope == .week ? "Previous week" : "Previous day")
                Button("Today") { date = Calendar.current.startOfDay(for: .now) }
                Button { navigate(1) } label: { Image(systemName: "chevron.right") }
                    .help(scope == .week ? "Next week" : "Next day")
                    .accessibilityLabel(scope == .week ? "Next week" : "Next day")
                DatePicker("Go to date", selection: $date, displayedComponents: .date)
                    .labelsHidden().datePickerStyle(.field).fixedSize()
                    .accessibilityLabel("Go to calendar date")
                Spacer(minLength: 0)
            }.controlSize(.small)
            HStack {
                Text(rangeLabel).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.ink)
                Spacer(minLength: 8)
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Find tasks", text: $search).textFieldStyle(.plain)
                        .focused($searchFocused).accessibilityLabel("Search calendar tasks")
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).accessibilityLabel("Clear calendar search")
                    }
                }
                .font(.system(size: 11)).padding(7).frame(width: 150)
                .background(Palette.sidebar, in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 14)
    }

    private var rangeLabel: String {
        guard let first = days.first, let last = days.last else { return "" }
        if scope == .day { return first.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()) }
        return "\(first.formatted(.dateTime.month(.abbreviated).day())) – \(last.formatted(.dateTime.month(.abbreviated).day().year()))"
    }

    private var flexibleTray: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button { showingFlexible.toggle() } label: {
                HStack(spacing: 7) {
                    Image(systemName: showingFlexible ? "chevron.down" : "chevron.right")
                    Text("FLEXIBLE TASKS").tracking(1.1)
                    Text("\(flexible.count)").foregroundStyle(.tertiary)
                    Spacer()
                    Text("Drop here to remove a start time").font(.system(size: 10)).foregroundStyle(.secondary)
                }.font(.system(size: 10, weight: .semibold))
            }.buttonStyle(.plain).foregroundStyle(Palette.ink)
            if showingFlexible {
                if flexible.isEmpty {
                    Text(search.isEmpty ? "Unscheduled tasks appear here. Drag a calendar task back here to free its time."
                         : "No matching flexible tasks.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(flexible) { item in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                    Text([item.durationLabel ?? "No estimate",
                                          item.dueDate?.formatted(.dateTime.month(.abbreviated).day()) ?? "No date"]
                                        .joined(separator: " · "))
                                        .font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                                .frame(width: 165, alignment: .leading).padding(10)
                                .background(Palette.card, in: RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                                .onTapGesture { openDetails(item) }
                                .onDrag { dragProvider(for: item) }
                                .contextMenu { Button("Schedule…") { editor = CalendarEditRequest(item: item, date: date) } }
                                .accessibilityElement(children: .combine)
                                .accessibilityAddTraits(.isButton)
                                .accessibilityAction { openDetails(item) }
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(Palette.sidebar.opacity(0.5))
        .dropDestination(for: String.self) { tokens, _ in
            guard let item = draggedItem(tokens) else { return false }
            return makeFlexible(item)
        }
    }

    private func dayHeaders(columnWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text("24h").font(.system(size: 10)).foregroundStyle(.secondary).frame(width: gutter)
            ForEach(days, id: \.self) { day in
                Button {
                    date = day
                    scope = .day
                } label: {
                    VStack(spacing: 3) {
                        Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                            .font(.system(size: 10, weight: .medium)).tracking(1)
                        Text(day.formatted(.dateTime.day())).font(.system(size: 19, design: .rounded))
                    }
                    .foregroundStyle(Calendar.current.isDateInToday(day) ? Palette.green : Palette.ink)
                    .frame(width: columnWidth, height: 54)
                    .background(Calendar.current.isDateInToday(day) ? Palette.selection.opacity(0.55) : .clear)
                }
                .buttonStyle(.plain).help("Show \(day.formatted(date: .complete, time: .omitted))")
            }
        }
        .background(Palette.background)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var timeRuler: some View {
        VStack(spacing: 0) {
            ForEach(0..<24) { hour in
                Text(TodoItem.timeLabel(hour * 60))
                    .font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                    .frame(width: gutter, height: hourHeight, alignment: .top).id(hour)
            }
        }
        .scrollTargetLayout()
    }

    private func navigate(_ direction: Int) {
        date = Calendar.current.date(byAdding: .day, value: direction * (scope == .week ? 7 : 1), to: date) ?? date
    }

    private func openDetails(_ item: TodoItem) {
        selectedItemID = item.persistentModelID
        showingInspector = true
    }

    private func draggedItem(_ tokens: [String]) -> TodoItem? {
        guard tokens.count == 1, let token = tokens.first, token.hasPrefix("todoloo.calendar:") else { return nil }
        let identifier = String(token.dropFirst("todoloo.calendar:".count))
        return items.first { !$0.isCompleted && $0.reminderIdentifier == identifier }
    }

    private func move(_ tokens: [String], to day: Date, minute: Int) -> Bool {
        guard let item = draggedItem(tokens) else { return false }
        return change(item, actionName: "Move task") {
            CalendarPlacement.move(item, to: day, minute: minute)
        }
    }

    @discardableResult
    private func makeFlexible(_ item: TodoItem) -> Bool {
        change(item, actionName: "Remove start time") {
            item.setStartTime(nil)
            return true
        }
    }

    private func change(_ item: TodoItem, actionName: String, mutation: () -> Bool) -> Bool {
        let previous = (item.title, item.dueDate, item.startMinuteOfDay, item.durationMinutes, item.reminderIdentifier)
        let undo = modelContext.undoManager
        undo?.beginUndoGrouping()
        defer { undo?.endUndoGrouping() }
        guard mutation() else {
            error = "That time doesn’t occur on this date because the clocks change. Choose another 15-minute slot."
            return false
        }
        do {
            try modelContext.save()
            undo?.setActionName(actionName)
            selectedItemID = item.persistentModelID
            if let time = item.startTimeLabel, let day = item.dueDate {
                feedback = "\(item.title) · \(day.formatted(.dateTime.month(.abbreviated).day())) at \(time)."
                if item.remindersEnabled, let start = item.scheduledStart(), start.addingTimeInterval(-900) <= .now {
                    feedback += " The reminder time has passed."
                }
            } else { feedback = "\(item.title) is now flexible. Its date and estimate are kept." }
            return true
        } catch {
            item.title = previous.0
            item.dueDate = previous.1
            item.startMinuteOfDay = previous.2
            item.durationMinutes = previous.3
            item.reminderIdentifier = previous.4
            self.error = error.localizedDescription
            return false
        }
    }

    private func saveEditor(_ request: CalendarEditRequest, title: String, day: Date, minute: Int, duration: Int?) -> Bool {
        if let item = request.item {
            return change(item, actionName: "Reschedule task") {
                guard CalendarPlacement.move(item, to: day, minute: minute) else { return false }
                item.title = title
                item.durationMinutes = duration
                return true
            }
        }
        let item = TodoItem(title: title)
        guard CalendarPlacement.move(item, to: day, minute: minute) else {
            error = "That time doesn’t occur on this date because the clocks change. Choose another time."
            return false
        }
        item.durationMinutes = duration
        modelContext.insert(item)
        do {
            try modelContext.save()
            date = day
            selectedItemID = item.persistentModelID
            feedback = "Added \(item.title) at \(item.startTimeLabel ?? "")."
            return true
        } catch {
            modelContext.delete(item)
            self.error = error.localizedDescription
            return false
        }
    }
}

private func dragProvider(for item: TodoItem) -> NSItemProvider {
    if item.reminderIdentifier == nil { item.reminderIdentifier = UUID().uuidString }
    return NSItemProvider(object: "todoloo.calendar:\(item.reminderIdentifier!)" as NSString)
}

private struct CalendarDayColumn: View {
    let day: Date
    let width: CGFloat
    let hourHeight: CGFloat
    let blocks: [CalendarBlock]
    let selectedItemID: PersistentIdentifier?
    let open: (TodoItem) -> Void
    let edit: (TodoItem) -> Void
    let create: (Int) -> Void
    let drop: ([String], Int) -> Bool
    let makeFlexible: (TodoItem) -> Bool
    @State private var targeted = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(targeted ? Palette.selection.opacity(0.45) : Palette.card.opacity(0.35))
            Path { path in
                for quarter in 0...96 {
                    let y = CGFloat(quarter) * hourHeight / 4
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: width, y: y))
                }
            }.stroke(Palette.green.opacity(0.07), lineWidth: 0.5)
            Path { path in
                path.move(to: .zero)
                path.addLine(to: CGPoint(x: 0, y: hourHeight * 24))
                for hour in 0...24 {
                    let y = CGFloat(hour) * hourHeight
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: width, y: y))
                }
            }.stroke(Palette.green.opacity(0.15), lineWidth: 0.5)
            ForEach(blocks) { block in
                event(block)
            }
            TimelineView(.periodic(from: .now, by: 60)) { context in
                if Calendar.current.isDate(context.date, inSameDayAs: day) {
                    let parts = Calendar.current.dateComponents([.hour, .minute], from: context.date)
                    let minute = CGFloat((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
                    Rectangle().fill(Color.orange).frame(height: 1)
                        .overlay(alignment: .leading) { Circle().fill(Color.orange).frame(width: 5, height: 5) }
                        .offset(y: minute / 60 * hourHeight).allowsHitTesting(false)
                }
            }.allowsHitTesting(false)
        }
        .frame(width: width, height: hourHeight * 24)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, coordinateSpace: .local) { point in
            create(CalendarPlacement.snappedMinute(point.y / hourHeight * 60))
        }
        .dropDestination(for: String.self) { tokens, point in
            drop(tokens, CalendarPlacement.snappedMinute(point.y / hourHeight * 60))
        } isTargeted: { targeted = $0 }
    }

    private func event(_ block: CalendarBlock) -> some View {
        let laneWidth = (width - 6) / CGFloat(block.laneCount)
        let height = CGFloat(block.endMinute - block.startMinute) / 60 * hourHeight - 2
        let selected = selectedItemID == block.id
        let timing = block.item.plannedTimeLabel() ?? ""
        let hint = block.item.durationMinutes == nil
            ? "No estimate; shown as 30 minutes." : "Drag to move. Right-click to reschedule."
        let tooltip = [block.item.title, timing, hint].joined(separator: "\n")
        let spokenLabel = [block.item.title, timing, block.item.durationLabel ?? "no estimate"].joined(separator: ", ")
        let card = VStack(alignment: .leading, spacing: 3) {
            Text((block.continuesFromPreviousDay ? "↳ " : "") + block.item.title)
                .font(.system(size: 11, weight: .medium)).lineLimit(height >= 65 ? 2 : 1)
            if height >= 38 {
                Text(block.item.plannedTimeLabel() ?? "").font(.system(size: 9)).monospacedDigit()
                    .lineLimit(1)
            }
            if height >= 65 && block.item.durationMinutes == nil {
                Text("No estimate").font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 7).padding(.vertical, height < 30 ? 2 : 5)
        .frame(width: max(laneWidth - 3, 1), height: max(height, 18), alignment: .topLeading)
        .background(selected ? Palette.selection : Palette.selection.opacity(0.7), in: RoundedRectangle(cornerRadius: 5))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(block.item.listName == "Work" ? Color.blue : Palette.green)
                .frame(width: 3)
        }
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(selected ? Palette.green : .clear, lineWidth: 1))
        .clipped()
        .contentShape(Rectangle())
        return card
        .onTapGesture { open(block.item) }
        .onDrag { dragProvider(for: block.item) }
        .contextMenu { eventMenu(block.item) }
        .help(tooltip)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { open(block.item) }
        .accessibilityAction(named: Text("Reschedule")) { edit(block.item) }
        .offset(x: CGFloat(block.lane) * laneWidth + 4, y: CGFloat(block.startMinute) / 60 * hourHeight + 1)
    }

    @ViewBuilder
    private func eventMenu(_ item: TodoItem) -> some View {
        Button("Edit details") { open(item) }
        Button("Reschedule…") { edit(item) }
        Button("Make flexible") { _ = makeFlexible(item) }
        Divider()
        Button("Complete task") { item.setCompleted(true) }
    }
}

private struct CalendarEditRequest: Identifiable {
    let id = UUID()
    var item: TodoItem?
    var date: Date
    var minute: Int

    init(item: TodoItem? = nil, date: Date = .now, minute: Int = 540) {
        self.item = item
        self.date = item?.dueDate ?? date
        self.minute = item?.startMinuteOfDay ?? minute
    }
}

private struct CalendarTaskEditor: View {
    let request: CalendarEditRequest
    let save: (String, Date, Int, Int?) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var date: Date
    @State private var minute: Int
    @State private var hasEstimate: Bool
    @State private var duration: Int
    @State private var validationError: String?
    @FocusState private var titleFocused: Bool

    init(request: CalendarEditRequest, save: @escaping (String, Date, Int, Int?) -> Bool) {
        self.request = request
        self.save = save
        _title = State(initialValue: request.item?.title ?? "")
        _date = State(initialValue: request.date)
        _minute = State(initialValue: request.minute)
        _hasEstimate = State(initialValue: request.item == nil || request.item?.durationMinutes != nil)
        _duration = State(initialValue: request.item?.durationMinutes ?? 30)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(request.item == nil ? "Make a little time." : "Move your plan.")
                .font(.system(size: 26, design: .serif)).foregroundStyle(Palette.ink)
            TextField("Task title", text: $title).textFieldStyle(.roundedBorder)
                .focused($titleFocused).accessibilityLabel("Calendar task title")
            DatePicker("Date", selection: $date, displayedComponents: .date)
            HStack {
                Text("Start time")
                Spacer()
                Picker("Hour", selection: Binding(get: { minute / 60 }, set: { minute = $0 * 60 + minute % 60 })) {
                    ForEach(0..<24) { Text(String(format: "%02d", $0)).tag($0) }
                }.labelsHidden().frame(width: 65).accessibilityLabel("Calendar start hour")
                Text(":")
                Picker("Minute", selection: Binding(get: { minute % 60 }, set: { minute = minute / 60 * 60 + $0 })) {
                    ForEach([0, 15, 30, 45], id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                }.labelsHidden().frame(width: 65).accessibilityLabel("Calendar start minute")
            }
            Toggle("Estimated time", isOn: $hasEstimate)
            if hasEstimate {
                HStack {
                    TextField("Minutes", value: $duration, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder).frame(width: 70).accessibilityLabel("Calendar estimated minutes")
                    Text("minutes").foregroundStyle(.secondary)
                    Spacer()
                    ForEach([15, 30, 60], id: \.self) { value in
                        Button(TodoItem.estimateLabel(value)) { duration = value }.controlSize(.small)
                    }
                }
            }
            Text(request.item?.remindersEnabled == false
                 ? "Reminders are turned off for this task."
                 : "Reminder: 15 minutes before the start, when that time is still ahead.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            if let validationError { Text(validationError).font(.system(size: 11)).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(request.item == nil ? "Add task" : "Save changes") {
                    if hasEstimate && !(1...1440).contains(duration) {
                        validationError = "Choose an estimate between 1 and 1,440 minutes."
                    } else if save(title.trimmingCharacters(in: .whitespacesAndNewlines), date, minute, hasEstimate ? duration : nil) {
                        dismiss()
                    } else {
                        validationError = "Couldn’t save this time. Check the date and time, then try again."
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(28).frame(width: 400).background(Palette.background)
        .onAppear { titleFocused = true }
    }
}
