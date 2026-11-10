import SwiftData
import SwiftUI

enum CalendarDropTarget: Equatable {
    case time(day: Date, minute: Int)
    case flexible
}

struct CalendarDayFramesKey: PreferenceKey {
    static let defaultValue: [Date: CGRect] = [:]
    static func reduce(value: inout [Date: CGRect], nextValue: () -> [Date: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

struct CalendarViewportKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        // Unmeasured siblings contribute the default value. They must not erase
        // the rectangle emitted by the actual calendar viewport or tray.
        let next = nextValue()
        if next != .zero { value = next }
    }
}

struct CalendarTrayFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        // Unmeasured siblings contribute the default value. They must not erase
        // the rectangle emitted by the actual calendar viewport or tray.
        let next = nextValue()
        if next != .zero { value = next }
    }
}

struct CalendarVisibleFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        // Unmeasured siblings contribute the default value. They must not erase
        // the rectangle emitted by the actual calendar viewport or tray.
        let next = nextValue()
        if next != .zero { value = next }
    }
}

/// All coordinates are in the calendar surface, including the scroll view's current offset.
enum CalendarDragGeometry {
    static func destination(at point: CGPoint, grabOffset: CGFloat, days: [Date: CGRect],
                            viewport: CGRect, tray: CGRect, hourHeight: CGFloat) -> CalendarDropTarget? {
        if tray.contains(point) { return .flexible }
        guard hourHeight > 0, viewport.contains(point),
              let (day, frame) = days.first(where: { point.x >= $0.value.minX && point.x < $0.value.maxX }) else { return nil }
        let minute = (point.y - frame.minY - grabOffset) / hourHeight * 60
        return .time(day: day, minute: CalendarPlacement.snappedMinute(minute))
    }
}

/// Direct manipulation: keep the grab point fixed and commit only on mouse-up.
@MainActor
final class CalendarDragState: ObservableObject {
    @Published private(set) var item: TodoItem?
    @Published private(set) var target: CalendarDropTarget?
    @Published private(set) var cancelled = false
    private(set) var grabOffset: CGFloat = 0
    private(set) var pointer: CGPoint?
    var dayFrames: [Date: CGRect] = [:] { didSet { refreshTarget() } }
    var viewport: CGRect = .zero { didSet { refreshTarget() } }
    var visibleFrame: CGRect = .zero { didSet { refreshTarget() } }
    var tray: CGRect = .zero { didSet { refreshTarget() } }
    var candidates: [TodoItem] = []
    var conflicts: [TodoItem] {
        guard let item, case .time(let day, let minute) = target else { return [] }
        return CalendarPlacement.conflicts(for: item, on: day, minute: minute, among: candidates)
    }
    let hourHeight: CGFloat = 84

    var sourceID: PersistentIdentifier? { item?.persistentModelID }
    var title: String { item?.title ?? "" }
    var duration: Int { max(item?.durationMinutes ?? 30, 1) }
    var isActive: Bool { item != nil && !cancelled }
    private var dropViewport: CGRect { visibleFrame == .zero ? viewport : viewport.intersection(visibleFrame) }

    func begin(_ item: TodoItem, at point: CGPoint, day: Date? = nil, startMinute: Double? = nil) {
        guard self.item == nil else { return }
        self.item = item
        cancelled = false
        if let day, let startMinute, let frame = dayFrames[day] {
            let top = frame.minY + CGFloat(startMinute) / 60 * hourHeight
            grabOffset = max(0, point.y - top)
        } else { grabOffset = 10 }
        update(point)
    }

    func update(_ point: CGPoint) {
        guard isActive else { return }
        pointer = point
        refreshTarget()
    }

    private func refreshTarget() {
        guard isActive, let pointer else { return }
        let destination = CalendarDragGeometry.destination(at: pointer, grabOffset: grabOffset,
            days: dayFrames, viewport: dropViewport, tray: tray, hourHeight: hourHeight)
        if destination != target { target = destination }
    }

    var edgeScrollDirection: Int {
        guard isActive, let pointer, pointer.x >= dropViewport.minX, pointer.x <= dropViewport.maxX else { return 0 }
        if pointer.y >= dropViewport.minY && pointer.y < dropViewport.minY + 28 { return -1 }
        if pointer.y <= dropViewport.maxY && pointer.y > dropViewport.maxY - 28 { return 1 }
        return 0
    }

    func cancel() {
        cancelled = true
        target = nil
        // Retain the source until mouse-up so moving the held mouse cannot restart a cancelled drag.
    }

    func release() -> (TodoItem, CalendarDropTarget)? {
        defer { finish() }
        guard isActive, let item, let target, !item.isCompleted else { return nil }
        if case .time(let day, let minute) = target,
           CalendarPlacement.start(on: day, minute: minute) == nil { return nil }
        return (item, target)
    }

    func finish() {
        target = nil
        item = nil
        pointer = nil
        grabOffset = 0
        cancelled = false
    }
}
