import AppKit
import SwiftData
import SwiftUI

struct TodoListView: View {
    let filter: TodoFilter
    @Binding var selectedItemID: PersistentIdentifier?
    @Binding var showingInspector: Bool
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TodoItem.createdAt, order: .reverse) private var items: [TodoItem]
    @State private var draft = ""
    @State private var searchText = ""
    @AppStorage("taskSort") private var sort: TaskSort = .newest
    @State private var showCompleted = true
    @State private var saveError: String?
    @FocusState private var focus: Field?
    private enum Field { case composer, search }

    private func matchingItems(now: Date) -> [TodoItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return sort.ordered(items.filter {
            filter.includes($0, now: now) && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)
                || $0.notes.localizedCaseInsensitiveContains(query))
        })
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let matching = matchingItems(now: context.date)
            let active = matching.filter { !$0.isCompleted }
            let completed = matching.filter(\.isCompleted)
            let todayItems = items.filter { TodoFilter.today.includes($0, now: context.date) }
            VStack(alignment: .leading, spacing: 0) {
                topBar
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 26) {
                        header(now: context.date)
                        if filter == .today && !todayItems.isEmpty {
                            progressCard(active: todayItems.filter { !$0.isCompleted }.count, completed: todayItems.filter(\.isCompleted).count)
                        }
                        if filter != .completed { composer }
                        if matching.isEmpty {
                            emptyState
                        } else {
                            VStack(spacing: 18) {
                                if !active.isEmpty {
                                    taskSection(active, title: filter == .today ? "ON YOUR MIND" : "TO DO", now: context.date)
                                }
                                if !completed.isEmpty {
                                    VStack(spacing: 8) {
                                        Button {
                                            withAnimation(.easeInOut(duration: 0.2)) { showCompleted.toggle() }
                                        } label: {
                                            HStack(spacing: 8) {
                                                Image(systemName: showCompleted ? "chevron.down" : "chevron.right")
                                                Text("COMPLETED")
                                                Text("\(completed.count)").foregroundStyle(.tertiary)
                                                Spacer()
                                            }
                                            .font(.system(size: 10, weight: .semibold)).tracking(1.2)
                                            .foregroundStyle(.secondary).padding(.vertical, 8)
                                        }.buttonStyle(.plain)
                                        if showCompleted {
                                            rows(completed, now: context.date)
                                        }
                                    }
                                }
                            }
                        }
                        Spacer(minLength: 12)
                    }
                    .padding(.horizontal, 36).padding(.top, 20).padding(.bottom, 28)
                    .frame(maxWidth: 860)
                    .frame(maxWidth: .infinity)
                }
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle").foregroundStyle(Palette.green)
                    Text("\(active.count) remaining")
                    Spacer()
                    Text("New task").foregroundStyle(.tertiary)
                    Text("⌘ N").font(.system(size: 10, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 5).padding(.vertical, 3)
                        .background(Palette.sidebar, in: RoundedRectangle(cornerRadius: 4))
                }
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .padding(.horizontal, 36).padding(.vertical, 14)
                .overlay(alignment: .top) { Divider().opacity(0.5) }
            }
            .background(Palette.background)
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusNewTodoField)) { _ in focus = .composer }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearchField)) { _ in focus = .search }
        .onChange(of: filter) { _, _ in
            searchText = ""
            showCompleted = true
        }
        .onChange(of: items.map(\.persistentModelID)) { _, ids in
            if let selectedItemID, !ids.contains(selectedItemID) { self.selectedItemID = nil }
        }
        .alert("Couldn’t save your changes", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: { Text(saveError ?? "") }
    }

    private var topBar: some View {
        HStack {
            Label(filter.title, systemImage: filter.systemImage)
                .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            Spacer(minLength: 16)
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search this view", text: $searchText)
                    .textFieldStyle(.plain).focused($focus, equals: .search)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help("Clear search")
                }
            }
            .font(.system(size: 12)).padding(8)
            .frame(width: 190).background(Palette.sidebar.opacity(0.7), in: RoundedRectangle(cornerRadius: 7))
        }
        .padding(.horizontal, 36).padding(.top, 10).padding(.bottom, 8)
    }

    private func header(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(now.formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased())
                .font(.system(size: 10, weight: .medium)).tracking(1.6).foregroundStyle(.secondary)
            HStack(alignment: .center) {
                Text(filter.title).font(.system(size: 38, weight: .regular, design: .serif))
                    .tracking(-1.2).foregroundStyle(Palette.ink)
                Spacer()
                Menu {
                    Picker("Sort tasks", selection: $sort) {
                        ForEach(TaskSort.allCases) { Text($0.rawValue).tag($0) }
                    }
                } label: { Label("Sort", systemImage: "arrow.up.arrow.down") }
                    .menuStyle(.borderlessButton).fixedSize().font(.system(size: 12))
                    .help("Sort tasks: \(sort.rawValue)")
            }
            Text(filter.subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }

    private func progressCard(active: Int, completed: Int) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(Palette.green.opacity(0.12), lineWidth: 4)
                Circle().trim(from: 0, to: CGFloat(completed) / CGFloat(max(active + completed, 1)))
                    .stroke(Palette.green, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: active == 0 ? "checkmark" : "leaf")
                    .font(.system(size: 18, weight: .light)).foregroundStyle(Palette.green)
            }.frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 5) {
                Text(active == 0 ? "Look at you. All done." : "Small steps, a little more space.")
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(completed) of \(active + completed) tasks complete. \(active == 0 ? "Enjoy a moment for yourself." : "You’ve got this.")")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(18).background(Palette.selection.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private var composer: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus").font(.system(size: 17, weight: .light)).foregroundStyle(Palette.green)
            TextField("What would you like to get done?", text: $draft)
                .font(.system(size: 14)).textFieldStyle(.plain)
                .focused($focus, equals: .composer).onSubmit(addTodo)
                .accessibilityLabel("New task")
                .help("Try: Read a chapter (09:15) (30mins). Start times use 15-minute steps.")
            Button(action: addTodo) {
                Image(systemName: "arrow.up").font(.system(size: 12, weight: .semibold))
                    .frame(width: 27, height: 27)
                    .foregroundStyle(Palette.background)
                    .background(Palette.green, in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain).help("Add task (Return)").accessibilityLabel("Add task")
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(14).background(Palette.card, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(focus == .composer ? Palette.green.opacity(0.6) : Palette.green.opacity(0.17), lineWidth: 1))
    }

    private func taskSection(_ tasks: [TodoItem], title: String, now: Date) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(title).tracking(1.3)
                Text("\(tasks.count)").foregroundStyle(.tertiary)
                Spacer()
            }.font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).padding(.bottom, 5)
            rows(tasks, now: now)
        }
    }

    private func rows(_ tasks: [TodoItem], now: Date) -> some View {
        LazyVStack(spacing: 3) {
            ForEach(tasks) { item in
                TodoRowView(item: item, isSelected: selectedItemID == item.persistentModelID, now: now) {
                    selectedItemID = item.persistentModelID
                    showingInspector = true
                }
                .contextMenu {
                    Button("Edit details") { selectedItemID = item.persistentModelID; showingInspector = true }
                    Button(item.isCompleted ? "Mark incomplete" : "Complete task") { item.setCompleted(!item.isCompleted) }
                    Button(item.isImportant ? "Remove priority" : "Mark important") { item.isImportant.toggle() }
                    Menu("Move to") {
                        Button("Personal") { item.listName = "Personal" }
                        Button("Work") { item.listName = "Work" }
                    }
                    Button("Due today") { item.dueDate = Calendar.current.startOfDay(for: .now) }
                    Button("Due tomorrow") { item.dueDate = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)) }
                    Divider()
                    Button("Delete task", role: .destructive) { delete(item) }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Palette.selection.opacity(0.6)).frame(width: 82, height: 82)
                Image(systemName: searchText.isEmpty ? (filter == .completed ? "checkmark.seal" : "leaf") : "magnifyingglass")
                    .font(.system(size: 32, weight: .ultraLight)).foregroundStyle(Palette.green)
            }
            Text(searchText.isEmpty ? (filter == .completed ? "Good things take small steps." : "A little room to breathe.") : "No tasks found.")
                .font(.system(size: 23, design: .serif)).foregroundStyle(Palette.ink)
            Text(searchText.isEmpty ? emptyDescription : "Try another word, or clear your search.")
                .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .frame(maxWidth: 310)
            if searchText.isEmpty && filter != .completed {
                Button("Add your first task") { focus = .composer }
                    .buttonStyle(.bordered).padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }
    private var emptyDescription: String {
        switch filter {
        case .today: "Your day is a blank page. Add something you’d like to make time for."
        case .upcoming: "Nothing scheduled ahead. New tasks here are set for tomorrow."
        case .completed: "The tasks you finish will find a home here."
        case .important: "Flag a task to keep what matters close at hand."
        default: "Get it out of your head and into your list. Start with one small thing."
        }
    }
    private func addTodo() {
        let parsed = TodoItem.parseDraft(draft)
        guard !parsed.title.isEmpty else { return }
        let item = TodoItem(title: parsed.title)
        item.durationMinutes = parsed.durationMinutes
        if filter == .today { item.dueDate = Calendar.current.startOfDay(for: .now) }
        if filter == .upcoming { item.dueDate = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)) }
        if let start = parsed.startMinuteOfDay { item.setStartTime(start) }
        item.listName = filter == .work ? "Work" : "Personal"
        item.isImportant = filter == .important
        modelContext.insert(item)
        do {
            try modelContext.save()
            draft = ""
            searchText = ""
            selectedItemID = item.persistentModelID
            focus = .composer
        } catch {
            // A retry should not insert a second copy of the unsaved task.
            modelContext.delete(item)
            saveError = error.localizedDescription
        }
    }
    private func delete(_ item: TodoItem) {
        if selectedItemID == item.persistentModelID { selectedItemID = nil }
        focus = nil
        NSApp.keyWindow?.makeFirstResponder(nil)
        modelContext.delete(item)
        do { try modelContext.save() } catch { saveError = error.localizedDescription }
    }
}
