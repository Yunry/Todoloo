import AppKit
import SwiftData
import SwiftUI

@main
struct TodolooApp: App {
    @NSApplicationDelegateAdaptor(TodolooAppDelegate.self) private var appDelegate
    private let demo = ProcessInfo.processInfo.arguments.contains("--demo")
    var body: some Scene {
        Window("Todoloo", id: "main") {
            ContentView()
        }
        .modelContainer(for: TodoItem.self, inMemory: demo, isUndoEnabled: true) { result in
            if demo, case .success(let container) = result {
                let context = container.mainContext
                let examples: [(String, String, Int, Bool, Bool)] = [
                    ("Make time for a little fresh air", "Personal", 0, false, false),
                    ("Pick up something good for dinner", "Personal", 0, false, false),
                    ("Send the first draft to the team", "Work", 0, true, false),
                    ("Sketch a few ideas for the week", "Work", 0, false, false),
                    ("A quiet coffee and a plan for the day", "Personal", 0, false, true),
                    ("Book a table for Friday", "Personal", 2, false, false),
                    ("Review the project timeline", "Work", 1, true, false)
                ]
                for (index, example) in examples.enumerated() {
                    let task = TodoItem(title: example.0)
                    task.listName = example.1
                    task.dueDate = Calendar.current.date(byAdding: .day, value: example.2, to: Calendar.current.startOfDay(for: .now))
                    task.isImportant = example.3
                    task.setCompleted(example.4)
                    task.createdAt = .now.addingTimeInterval(Double(-index * 60))
                    if index == 2 { task.notes = "A fresh pair of eyes always helps. Include the latest mockups and a short summary of what changed." }
                    context.insert(task)
                }
                try? context.save()
            }
        }
        .defaultSize(width: 1050, height: 760)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Task") {
                    NotificationCenter.default.post(name: .focusNewTodoField, object: nil)
                }.keyboardShortcut("n")
            }
            CommandGroup(after: .textEditing) {
                Button("Find Tasks") {
                    NotificationCenter.default.post(name: .focusSearchField, object: nil)
                }.keyboardShortcut("f")
            }
        }
    }
}

@MainActor
final class TodolooAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Refresh the running Dock tile even if Launch Services cached an earlier icon-less build.
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
            NSApp.dockTile.display()
        }
    }
}
