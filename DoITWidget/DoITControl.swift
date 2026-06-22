// DoIT Control Center control — one-tap Quick Add (FR-WIDGET-070, iOS 18+).
//
// REFERENCE CODE — not yet compiled (needs the widget extension target; see Widget/README.md).
// A `ControlWidget` puts a button in Control Center / the Lock Screen control slots. Tapping it opens
// the app and raises a "pending quick-add" flag in the shared App-Group store; the app reads that flag
// on foreground and presents Quick Add (the small app-side hook noted in the README).

import WidgetKit
import SwiftUI
import AppIntents

@available(iOS 18.0, *)
struct QuickAddControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "DoITQuickAddControl") {
            ControlWidgetButton(action: OpenQuickAddIntent()) {
                Label("Add task", systemImage: "plus.circle.fill")
            }
        }
        .displayName("DoIT Quick Add")
        .description("Capture a task in DoIT.")
    }
}

@available(iOS 18.0, *)
struct OpenQuickAddIntent: AppIntent {
    static var title: LocalizedStringResource = "Quick add a task in DoIT"
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        // Raise a shared flag; the app reads `doit.pendingQuickAdd` on foreground and presents Quick Add.
        let defaults = UserDefaults(suiteName: "group.app.doit") ?? .standard
        defaults.set(true, forKey: "doit.pendingQuickAdd")
        return .result()
    }
}

/// Interactive "complete" button on the Today widget. Runs in the widget process (no app launch), so
/// it queues the task id into the shared App Group; the app drains `doit.pendingComplete` on foreground
/// and completes each through the normal mutation path (widget-driven edit → app's next foreground sync).
struct CompleteTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete a DoIT task"

    @Parameter(title: "Task ID") var taskId: String

    init() {}
    init(taskId: String) { self.taskId = taskId }

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: "group.app.doit") ?? .standard
        var pending = defaults.stringArray(forKey: "doit.pendingComplete") ?? []
        if !pending.contains(taskId) { pending.append(taskId) }
        defaults.set(pending, forKey: "doit.pendingComplete")
        return .result()
    }
}
