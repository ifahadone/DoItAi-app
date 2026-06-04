# DoIT Agenda Widget (P1-J)

Reference implementation of the home-screen agenda widget + interactive App Intents. The widget
**code, data contract, and intents are done**; wiring the widget **extension target** is the
remaining step, and it is inherently device/signing-bound (so it is not buildable in the headless
simulator setup).

## What's already implemented (and built/tested)

- **`SyncCore/AgendaSnapshot.swift`** — the widget's data contract (`AgendaSnapshot` / `AgendaItem`)
  + `AgendaSnapshotStore` (read/write to a shared `UserDefaults` suite). Unit-tested.
- **`App/AppServices.publishAgenda()`** — builds today's + overdue tasks (via the tested
  `SmartListClassifier`) into an `AgendaSnapshot` and writes it to the App-Group store on each sync.
- **`App/Features/Intents/TaskIntents.swift`** — `CompleteTaskIntent` + `SnoozeReminderIntent`
  (App Intents). They compile in the app target and already work from Shortcuts/Siri.
- **`Widget/DoITAgendaWidget.swift`** (this folder) — the `WidgetBundle` + `TimelineProvider` + view,
  reading the snapshot and using `CompleteTaskIntent` for in-place completion.
- **`Widget/DoITSectographWidget.swift`** (P2-6) — a home/lock **day-dial** widget that reuses
  `DesignSystem.SectographView` over the snapshot's scheduled blocks (same layout core as the app).
- **`Widget/FocusLiveActivity.swift`** (P2-4) — the running-focus-block **Live Activity** (lock screen
  + Dynamic Island), reusing the `FocusSession` fields.

Decoupling: the widget reads a published snapshot, so it depends only on `SyncCore` — never on the
app's SwiftData models.

## Remaining integration (needs Xcode + a signed device)

1. **Add a Widget Extension target** to `DoIT.xcodeproj` (e.g. `DoITWidget`). Move
   `Widget/DoITAgendaWidget.swift` into it and add `SyncCore` as a dependency.
2. **App Groups capability** (`group.app.doit`) on **both** the app and widget targets. This needs a
   real bundle id + provisioning profile — until then the app falls back to the per-process default
   store (the simulator warning), so the snapshot can't cross processes.
3. **Share the intents with the widget target.** `CompleteTaskIntent` touches the app's `@Model`s +
   `PersistenceContainer`; the clean fix is to move the `@Model`s into a shared framework (or a Swift
   package) importable by both targets, then give the intents target membership in both.
4. **Sign + run on a device.** Widget rendering + the App Group both require signing.
5. **`WidgetCenter.shared.reloadAllTimelines()`** after each edit (add to `AppServices.publishAgenda`)
   so the widget refreshes promptly.

## Known follow-up: widget-driven edits + sync

`CompleteTaskIntent` toggles the task in the shared store, but the sync **outbox is currently
in-memory** (`AppServices`/`DefaultSyncEngine`), so an edit made while the app is suspended only
flushes to the server on the app's next foreground. Persisting the outbox in the shared SwiftData
store would let the widget/intent enqueue directly.
