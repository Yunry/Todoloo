import Foundation
import SwiftData

enum ListIcon: String, CaseIterable, Identifiable {
    case list = "list.bullet", folder = "folder", home = "house", book = "book.closed"
    case study = "graduationcap", heart = "heart", walk = "figure.walk", fitness = "dumbbell"
    case shopping = "cart", food = "fork.knife", travel = "airplane", car = "car"
    case art = "paintpalette", music = "music.note", games = "gamecontroller", nature = "leaf"
    case tools = "hammer", computer = "laptopcomputer", money = "banknote", star = "star"
    case goals = "target", ideas = "lightbulb", pets = "pawprint", people = "person.2"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .list: "List"
        case .folder: "Folder"
        case .home: "Home"
        case .book: "Reading"
        case .study: "Study"
        case .heart: "Wellbeing"
        case .walk: "Walking"
        case .fitness: "Fitness"
        case .shopping: "Shopping"
        case .food: "Food"
        case .travel: "Travel"
        case .car: "Car"
        case .art: "Art"
        case .music: "Music"
        case .games: "Games"
        case .nature: "Nature"
        case .tools: "Tools"
        case .computer: "Computer"
        case .money: "Money"
        case .star: "Star"
        case .goals: "Goals"
        case .ideas: "Ideas"
        case .pets: "Pets"
        case .people: "People"
        }
    }
}

@Model
final class TaskList {
    var name: String
    var createdAt: Date = Date.now
    var symbolName: String? = nil
    init(name: String, icon: ListIcon = .list) { self.name = name; self.symbolName = icon.rawValue }
}

enum ListCatalog {
    static let builtIn = ["Personal", "Work"]

    static func symbol(for name: String, lists: [TaskList]) -> String {
        if name == "Personal" { return "person" }
        if name == "Work" { return "briefcase" }
        return ListIcon(rawValue: lists.first { $0.name == name }?.symbolName ?? "")?.rawValue ?? ListIcon.list.rawValue
    }

    static func names(lists: [TaskList], items: [TodoItem]) -> [String] {
        let custom = Set(lists.map(\.name) + items.map(\.listName))
            .subtracting(builtIn).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return builtIn + custom
    }

    static func validatedName(_ value: String, existing: [String], replacing old: String? = nil) throws -> String {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ListError.empty }
        guard name.count <= 60 else { throw ListError.tooLong }
        let key = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        guard !existing.filter({ $0 != old }).contains(where: {
            $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) == key
        }) else { throw ListError.duplicate }
        return name
    }

    @MainActor
    @discardableResult
    static func create(_ value: String, icon: ListIcon = .list, in context: ModelContext) throws -> TaskList {
        let lists = try context.fetch(FetchDescriptor<TaskList>())
        let items = try context.fetch(FetchDescriptor<TodoItem>())
        let name = try validatedName(value, existing: names(lists: lists, items: items))
        let list = TaskList(name: name, icon: icon)
        context.undoManager?.beginUndoGrouping()
        defer { context.undoManager?.endUndoGrouping() }
        context.insert(list)
        do { try context.save(); context.undoManager?.setActionName("Create list") }
        catch { context.delete(list); throw error }
        return list
    }

    @MainActor
    static func rename(_ old: String, to value: String, icon: ListIcon? = nil, in context: ModelContext) throws -> String {
        guard !builtIn.contains(old) else { throw ListError.builtIn }
        let lists = try context.fetch(FetchDescriptor<TaskList>())
        let items = try context.fetch(FetchDescriptor<TodoItem>())
        let name = try validatedName(value, existing: names(lists: lists, items: items), replacing: old)
        if name == old && icon == nil { return name }
        let affected = items.filter { $0.listName == old }
        let existing = lists.first { $0.name == old }
        let list = existing ?? TaskList(name: old)
        let previousSymbol = list.symbolName
        context.undoManager?.beginUndoGrouping()
        defer { context.undoManager?.endUndoGrouping() }
        if existing == nil { context.insert(list) }
        if name != old {
            list.name = name
            for item in affected { item.listName = name }
        }
        if let icon { list.symbolName = icon.rawValue }
        context.processPendingChanges()
        do { try context.save(); context.undoManager?.setActionName(name == old ? "Change list icon" : "Edit list") }
        catch {
            list.name = old
            list.symbolName = previousSymbol
            for item in affected { item.listName = old }
            if existing == nil { context.delete(list) }
            throw error
        }
        return name
    }

    /// Removing a list keeps all tasks, including completed ones, in Personal.
    @MainActor
    static func remove(_ name: String, in context: ModelContext) throws {
        guard !builtIn.contains(name) else { throw ListError.builtIn }
        let lists = try context.fetch(FetchDescriptor<TaskList>()).filter { $0.name == name }
        let items = try context.fetch(FetchDescriptor<TodoItem>()).filter { $0.listName == name }
        context.undoManager?.beginUndoGrouping()
        defer { context.undoManager?.endUndoGrouping() }
        for item in items { item.listName = "Personal" }
        for list in lists { context.delete(list) }
        do { try context.save(); context.undoManager?.setActionName("Remove list") }
        catch {
            for item in items { item.listName = name }
            for list in lists { context.insert(list) }
            throw error
        }
    }
}

enum ListError: LocalizedError {
    case empty, duplicate, tooLong, builtIn
    var errorDescription: String? {
        switch self {
        case .empty: "Give your list a name."
        case .duplicate: "A list with that name already exists. Choose another name."
        case .tooLong: "Keep list names to 60 characters or fewer."
        case .builtIn: "Personal and Work are the default lists."
        }
    }
}

/// Keep the existing task store's schema unchanged when adding list metadata.
/// Both stores share one context, so list edits still participate in undo.
@MainActor
enum TaskStore {
    static func make(inMemory: Bool = false, taskURL: URL? = nil, listURL: URL? = nil) throws -> ModelContainer {
        let tasks: ModelConfiguration
        let lists: ModelConfiguration
        if inMemory {
            tasks = ModelConfiguration("Tasks", schema: Schema([TodoItem.self]), isStoredInMemoryOnly: true)
            lists = ModelConfiguration("Lists", schema: Schema([TaskList.self]), isStoredInMemoryOnly: true)
        } else {
            let support = URL.applicationSupportDirectory
            tasks = ModelConfiguration("Tasks", schema: Schema([TodoItem.self]), url: taskURL ?? support.appendingPathComponent("default.store"))
            lists = ModelConfiguration("Lists", schema: Schema([TaskList.self]), url: listURL ?? support.appendingPathComponent("TodolooLists.store"))
        }
        let container = try ModelContainer(for: TodoItem.self, TaskList.self, configurations: tasks, lists)
        container.mainContext.undoManager = UndoManager()
        return container
    }
}
