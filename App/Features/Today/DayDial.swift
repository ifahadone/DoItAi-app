import Foundation
import SyncCore
import DesignSystem

/// Builds the day-dial's blocks (+ display titles) from a day's tasks. Shared by the Today hero and
/// Focus mode so both render the identical day: scheduled tasks become span arcs; due-only tasks become
/// instant spokes; done tasks are flagged so the dial dims them. (Calendar keeps its own builder with
/// calendar-specific rules.)
enum DayDial {
    /// Day blocks for `tasks`, resolving each task's list color/icon from `lists`. Only items that fall
    /// on the same calendar day as `now` are included.
    static func items(tasks: [TaskModel], lists: [TaskListModel], now: Date,
                      calendar: Calendar = .current) -> [SectographItem] {
        func minute(_ date: Date) -> Int? {
            guard calendar.isDate(date, inSameDayAs: now) else { return nil }
            let c = calendar.dateComponents([.hour, .minute], from: date)
            return (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }
        func list(_ task: TaskModel) -> TaskListModel? {
            guard let listId = task.listId else { return nil }
            return lists.first { $0.id == listId }
        }
        return tasks.compactMap { task in
            let taskList = list(task)
            let color = taskList?.colorHex
            let icon = taskList?.icon
            let done = task.status == .done
            if let start = task.scheduledStart, let startMinute = minute(start) {
                let endMinute = task.scheduledEnd.flatMap(minute) ?? min(1440, startMinute + 60)
                return SectographItem(id: task.id, startMinute: startMinute, endMinute: endMinute,
                                      colorHex: color, kind: .span, symbolName: icon, isDone: done)
            } else if let due = task.dueAt, let dueMinute = minute(due) {
                // Due-only tasks read as instant markers (a dashed spoke + the list icon), not fat arcs.
                return SectographItem(id: task.id, startMinute: dueMinute, endMinute: min(1440, dueMinute + 20),
                                      colorHex: color, kind: .instant, symbolName: icon, isDone: done)
            }
            return nil
        }
    }

    /// On-arc display titles keyed by item id (the task title).
    static func titles(tasks: [TaskModel], items: [SectographItem]) -> [String: String] {
        var result: [String: String] = [:]
        for item in items {
            if let task = tasks.first(where: { $0.id == item.id }) { result[item.id] = task.title }
        }
        return result
    }
}
