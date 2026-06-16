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
