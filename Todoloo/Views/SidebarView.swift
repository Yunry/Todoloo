import AppKit
import SwiftData
import SwiftUI

struct SidebarView: View {
    @Binding var filter: TodoFilter
    @Query private var items: [TodoItem]
    @Query private var lists: [TaskList]
    @Environment(\.modelContext) private var modelContext
    @State private var listEditor: ListEditorRequest?
    @State private var removingList: String?
    @State private var error: String?

    private var names: [String] { ListCatalog.names(lists: lists, items: items) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(Palette.background)
                        .frame(width: 34, height: 34)
                        .background(Palette.green, in: RoundedRectangle(cornerRadius: 11))
                    Text("todoloo").font(.system(size: 25, weight: .semibold, design: .rounded)).tracking(-1)
                }
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 30)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        caption("YOUR SPACE")
                        ForEach([TodoFilter.today, .calendar, .upcoming, .all, .important, .completed]) { item in
                            navigationRow(item, now: context.date)
                        }
                        HStack {
                            Text("MY LISTS").font(.system(size: 10, weight: .semibold)).tracking(1.5)
                            Spacer()
                            Button { listEditor = ListEditorRequest() } label: { Image(systemName: "plus") }
                                .buttonStyle(.plain).help("New list").accessibilityLabel("New list")
                        }.foregroundStyle(.secondary).padding(.horizontal, 24).padding(.top, 28).padding(.bottom, 10)
                        ForEach(names, id: \.self) { name in
                            navigationRow(.list(name), now: context.date)
                                .contextMenu {
                                    if !ListCatalog.builtIn.contains(name) {
                                        Button("Edit list…") {
                                            listEditor = ListEditorRequest(oldName: name, icon: ListIcon(rawValue: ListCatalog.symbol(for: name, lists: lists)) ?? .list)
                                        }
                                        Button("Remove list…") { removingList = name }
                                    }
                                }
                        }
                    }
                }.frame(maxHeight: .infinity, alignment: .top)
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "leaf").font(.system(size: 22, weight: .light))
                    Text("One thing at a time.").font(.system(size: 14, weight: .medium, design: .serif))
                    Text("A little progress goes a long way.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .foregroundStyle(Palette.green).padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 12)).padding(14)
                Label("On this Mac", systemImage: "internaldrive")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .padding(.horizontal, 22).padding(.bottom, 18)
            }.background(Palette.sidebar)
        }
        .onReceive(NotificationCenter.default.publisher(for: .newTaskList)) { _ in listEditor = ListEditorRequest() }
        .sheet(item: $listEditor) { request in
            ListEditorSheet(request: request) { name in
                if request.oldName == nil || filter.listName == request.oldName { filter = .list(name) }
            }
        }
        .alert("Remove list?", isPresented: Binding(get: { removingList != nil }, set: { if !$0 { removingList = nil } })) {
            Button("Cancel", role: .cancel) { removingList = nil }
            Button("Remove list") {
                guard let name = removingList else { return }
                do {
                    try ListCatalog.remove(name, in: modelContext)
                    if filter.listName == name { filter = .personal }
                } catch { self.error = error.localizedDescription }
                removingList = nil
            }
        } message: {
            Text("All tasks in \(removingList ?? "this list"), including completed tasks, will move to Personal. Use ⌘Z to undo.")
        }
        .alert("Couldn’t update your lists", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
        .onChange(of: names) { _, available in
            if case .custom(let name) = filter, !available.contains(name) { filter = .all }
        }
    }

    private func caption(_ title: String) -> some View {
        Text(title).font(.system(size: 10, weight: .semibold)).tracking(1.5)
            .foregroundStyle(.secondary).padding(.horizontal, 24).padding(.bottom, 10)
    }

    private func navigationRow(_ item: TodoFilter, now: Date) -> some View {
        let count = items.filter { item.includes($0, now: now) && (item == .completed || !$0.isCompleted) }.count
        return Button { filter = item } label: {
            HStack(spacing: 11) {
                Image(systemName: item.listName.map { ListCatalog.symbol(for: $0, lists: lists) } ?? item.systemImage).font(.system(size: 15)).frame(width: 20)
                    .foregroundStyle(item == .personal ? Color.orange : item == .work ? Color.blue : Palette.green)
                Text(item.title).font(.system(size: 13, weight: filter == item ? .semibold : .regular)).lineLimit(1)
                Spacer(minLength: 4)
                if count > 0 && item != .calendar {
                    Text("\(count)").font(.system(size: 11, weight: .medium)).monospacedDigit()
                        .foregroundStyle(filter == item ? Palette.green : .secondary)
                }
            }
            .foregroundStyle(Palette.ink).padding(.horizontal, 12).padding(.vertical, 11)
            .background(filter == item ? Palette.selection : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(item.title)
        .accessibilityAddTraits(filter == item ? .isSelected : [])
        .padding(.horizontal, 12).padding(.vertical, 1)
    }
}

private struct ListEditorRequest: Identifiable {
    let id = UUID()
    var oldName: String? = nil
    var icon: ListIcon = .list
}

private struct ListEditorSheet: View {
    let request: ListEditorRequest
    let saved: (String) -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var icon: ListIcon
    @State private var error: String?
    @FocusState private var focused: Bool

    init(request: ListEditorRequest, saved: @escaping (String) -> Void) {
        self.request = request; self.saved = saved
        _name = State(initialValue: request.oldName ?? "")
        _icon = State(initialValue: request.icon)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(request.oldName == nil ? "A list of your own." : "Edit your list.")
                .font(.system(size: 26, design: .serif))
            TextField("List name", text: $name).textFieldStyle(.roundedBorder)
                .focused($focused).accessibilityLabel("List name").onSubmit(save)
            Text(request.oldName == nil ? "A space for a project, a hobby, or whatever is on your mind."
                 : "Tasks in this list will keep their dates, notes, and reminders.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            iconPicker
            if let error { Text(error).font(.system(size: 11)).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(request.oldName == nil ? "Create list" : "Save changes", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(26).frame(width: 380).background(Palette.background).foregroundStyle(Palette.ink)
        .onAppear { focused = true }
    }

    private var iconPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Icon").fontWeight(.medium)
                Spacer()
                Text(icon.label).foregroundStyle(.secondary)
            }.font(.system(size: 12))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                ForEach(ListIcon.allCases) { option in
                    Button { icon = option } label: {
                        Image(systemName: option.rawValue).font(.system(size: 19))
                            .frame(maxWidth: .infinity).frame(height: 38)
                            .foregroundStyle(Palette.green)
                            .background(icon == option ? Palette.selection : Palette.sidebar, in: RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(icon == option ? Palette.green : .clear, lineWidth: 1))
                            .contentShape(RoundedRectangle(cornerRadius: 7))
                    }.buttonStyle(.plain).help(option.label).accessibilityLabel("Icon: " + option.label)
                        .accessibilityAddTraits(icon == option ? .isSelected : [])
                }
            }
        }
    }

    private func save() {
        // Register dialog edits with the parent window, rather than the sheet's
        // temporary text-editing undo manager, which disappears on dismissal.
        if let owner = NSApp.windows.first(where: { $0.attachedSheet != nil }),
           let manager = owner.undoManager {
            context.processPendingChanges()
            context.undoManager = manager
        }
        do {
            let result: String
            if let old = request.oldName { result = try ListCatalog.rename(old, to: name, icon: icon, in: context) }
            else { result = try ListCatalog.create(name, icon: icon, in: context).name }
            saved(result); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
