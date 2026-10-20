import AppKit
import SwiftData
import SwiftUI

enum Palette {
    static let green = adaptive(light: 0x27624D, dark: 0x9BCBB0)
    static let background = adaptive(light: 0xFCFBF7, dark: 0x202522)
    static let sidebar = adaptive(light: 0xF1F1E9, dark: 0x191E1B)
    static let card = adaptive(light: 0xFFFFFF, dark: 0x2A302C)
    static let selection = adaptive(light: 0xE2EBDF, dark: 0x35483B)
    static let ink = adaptive(light: 0x283A30, dark: 0xE6EAE3)

    private static func adaptive(light: Int, dark: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
}

struct ContentView: View {
    @State private var filter: TodoFilter = .today
    @State private var selectedItemID: PersistentIdentifier?
    @State private var showingInspector = false
    @Query private var items: [TodoItem]
    @StateObject private var reminders = ReminderScheduler()

    private var reminderPlans: [TaskReminder] {
        items.compactMap { $0.reminderPlan(now: .distantPast) }.sorted { $0.id < $1.id }
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(filter: $filter)
                .navigationSplitViewColumnWidth(min: 210, ideal: 224, max: 260)
        } detail: {
            HStack(spacing: 0) {
                Group {
                    if filter == .calendar {
                        TaskCalendarView(selectedItemID: $selectedItemID, showingInspector: $showingInspector)
                    } else {
                        TodoListView(filter: filter, selectedItemID: $selectedItemID, showingInspector: $showingInspector)
                    }
                }.frame(minWidth: 460, maxWidth: .infinity)
                if showingInspector {
                    Divider()
                    TodoInspectorView(itemID: selectedItemID)
                        .frame(width: 290)
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    showingInspector.toggle()
                } label: {
                    Label("Task details", systemImage: "sidebar.right")
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .help("Show task details (⌥⌘I)")
            }
        }
        .navigationTitle("")
        .tint(Palette.green)
        .environmentObject(reminders)
        .frame(minWidth: showingInspector ? 1000 : 760, minHeight: 600)
        .onReceive(NotificationCenter.default.publisher(for: .focusNewTodoField)) { _ in
            if filter == .completed { filter = .today }
        }
        .onChange(of: filter) { _, _ in selectedItemID = nil }
        .onChange(of: reminderPlans, initial: true) { _, plans in reminders.update(plans) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            reminders.update(reminderPlans)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            reminders.update(reminderPlans)
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
            reminders.update(reminderPlans)
        }
    }
}

#Preview {
    ContentView().modelContainer(for: TodoItem.self, inMemory: true)
}
