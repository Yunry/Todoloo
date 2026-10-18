import SwiftData
import SwiftUI

struct SidebarView: View {
    @Binding var filter: TodoFilter
    @Query private var items: [TodoItem]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(Palette.background)
                        .frame(width: 34, height: 34)
                        .background(Palette.green, in: RoundedRectangle(cornerRadius: 11))
                    Text("todoloo").font(.system(size: 25, weight: .semibold, design: .rounded))
                        .tracking(-1)
                }
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 36)
                caption("YOUR SPACE")
                ForEach([TodoFilter.today, .upcoming, .all, .important, .completed]) { item in
                    navigationRow(item, now: context.date)
                }
                caption("MY LISTS").padding(.top, 28)
                ForEach([TodoFilter.personal, .work]) { item in
                    navigationRow(item, now: context.date)
                }
                Spacer(minLength: 24)
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "leaf").font(.system(size: 22, weight: .light))
                    Text("One thing at a time.")
                        .font(.system(size: 14, weight: .medium, design: .serif))
                    Text("A little progress goes a long way.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .foregroundStyle(Palette.green)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
                .padding(14)
                Label("On this Mac", systemImage: "internaldrive")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .padding(.horizontal, 22).padding(.bottom, 18)
            }
            .background(Palette.sidebar)
        }
    }
    private func caption(_ title: String) -> some View {
        Text(title).font(.system(size: 10, weight: .semibold)).tracking(1.5)
            .foregroundStyle(.secondary).padding(.horizontal, 24).padding(.bottom, 10)
    }
    private func navigationRow(_ item: TodoFilter, now: Date) -> some View {
        let count = items.filter { item.includes($0, now: now) && (item == .completed || !$0.isCompleted) }.count
        return Button {
            filter = item
        } label: {
            HStack(spacing: 11) {
                Image(systemName: item.systemImage).font(.system(size: 15))
                    .frame(width: 20)
                    .foregroundStyle(item == .personal ? Color.orange : item == .work ? Color.blue : Palette.green)
                Text(item.title).font(.system(size: 13, weight: filter == item ? .semibold : .regular))
                Spacer()
                if count > 0 {
                    Text("\(count)").font(.system(size: 11, weight: .medium)).monospacedDigit()
                        .foregroundStyle(filter == item ? Palette.green : .secondary)
                }
            }
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background(filter == item ? Palette.selection : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(filter == item ? .isSelected : [])
        .padding(.horizontal, 12).padding(.vertical, 1)
    }
}
