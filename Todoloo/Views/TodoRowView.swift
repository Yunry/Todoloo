import SwiftData
import SwiftUI

struct TodoRowView: View {
    @Bindable var item: TodoItem
    var isSelected: Bool
    var now: Date
    var openDetails: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { item.setCompleted(!item.isCompleted) }
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21, weight: .light))
                    .foregroundStyle(item.isCompleted ? Palette.green : Palette.green.opacity(0.45))
                    .frame(width: 28, height: 34).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isCompleted ? "Reopen \(item.title)" : "Complete \(item.title)")
            Button(action: openDetails) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(item.title).font(.system(size: 14))
                        .strikethrough(item.isCompleted, color: .secondary)
                        .foregroundStyle(item.isCompleted ? .secondary : Palette.ink)
                        .lineLimit(2).multilineTextAlignment(.leading)
                    HStack(spacing: 10) {
                        HStack(spacing: 5) {
                            Circle().fill(item.listName == "Work" ? Color.blue.opacity(0.7) : Color.orange.opacity(0.7))
                                .frame(width: 5, height: 5)
                            Text(item.listName)
                        }
                        if let dueDate = item.dueDate {
                            Label(dateLabel(dueDate) + (item.plannedTimeLabel().map { " · " + $0 } ?? ""), systemImage: "calendar")
                                .foregroundStyle(item.isOverdue(relativeTo: now) ? Color(red: 0.75, green: 0.31, blue: 0.22) : .secondary)
                        }
                        if let duration = item.durationLabel {
                            Label("(\(duration))", systemImage: "clock")
                                .fixedSize()
                                .accessibilityLabel("Estimated time: \(duration)")
                        }
                        if !item.notes.isEmpty { Image(systemName: "text.alignleft").help("Has notes") }
                    }.font(.system(size: 10)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain).help("Edit task details")
            Button { item.isImportant.toggle() } label: {
                Image(systemName: item.isImportant ? "flag.fill" : "flag")
                    .font(.system(size: 12))
                    .foregroundStyle(item.isImportant ? Color.orange : .secondary)
                    .opacity(item.isImportant || isHovering || isSelected ? 1 : 0.25)
                    .frame(width: 26, height: 30).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isImportant ? "Remove priority from \(item.title)" : "Mark \(item.title) important")
        }
        .padding(.horizontal, 12).padding(.vertical, 13)
        .background(isSelected ? Palette.selection.opacity(0.65) : isHovering ? Palette.sidebar.opacity(0.6) : .clear,
                    in: RoundedRectangle(cornerRadius: 9))
        .onHover { isHovering = $0 }
    }
    private func dateLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) { return "Tomorrow" }
        return (item.isOverdue(relativeTo: now) ? "Overdue · " : "") + date.formatted(.dateTime.month(.abbreviated).day())
    }
}
