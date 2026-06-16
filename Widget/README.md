# DoIT widget & Live Activity suite (P1-J / P2-4 / P2-6 / P3-6)

Reference implementation of the full widget gallery + Live Activities. The **code, the shared data
contract, and the intents are done**; wiring the widget **extension target** is the remaining step,
and it is inherently device/signing-bound (so it is not buildable in the headless simulator setup).

## The suite

Home Screen (`Widget/DoITWidgetSuite.swift` + `Widget/DoITSectographWidget.swift`):
- **Up Next** (`.systemSmall`) — the block happening now + what's next, with the list color.
- **Today** (`.systemMedium` / `.systemLarge`) — a "X of Y done" progress + the agenda; each row has an
  interactive **complete** button (`CompleteTaskIntent`) and a list-color bar.
- **Day Dial** (`.systemSmall`) — the sectograph, reusing `DesignSystem.SectographView` over the
  snapshot's scheduled blocks (with their list colors) + the live now-hand — the same layout core as
  the app's Today hero (the Phase-2 DoD: one core → app + dial + widget).
- **Day Plan** (`.systemLarge`) — the dial + the rest of the day's agenda.
- **Streak** (`.systemSmall`) — the top habit's 🔥 streak + last-7-days mini heatmap.

Lock Screen (accessory families on the widgets above):
- **circular** — the day dial (Day Dial widget) and the streak gauge (Streak widget).
- **rectangular / inline** — now → next (Up Next widget).

Control Center / Lock-screen control (`Widget/DoITControl.swift`, iOS 18):
- **Quick Add** — `QuickAddControl` (`ControlWidget`) → opens the app + sets `doit.pendingQuickAdd`.

Live Activities + Dynamic Island:
- **Focus** (`Widget/FocusLiveActivity.swift`) — auto-advancing focus ring + elapsed timer + interactive
  **pause/resume + stop** (`ToggleFocusIntent` / `StopFocusIntent` LiveActivityIntents). Compact /
  expanded / minimal Dynamic Island.
- **Routine chain** (`Widget/AlarmLiveActivity.swift`) — current step + "step N of M" progress + a live
  countdown to the next step.

Decoupling: the widgets read a published `AgendaSnapshot`, so they depend only on `SyncCore` +
`DesignSystem` (for the dial) — never on the app's SwiftData models.

## What's already implemented (and built/tested)

- **`SyncCore/AgendaSnapshot.swift`** — the enriched contract: `AgendaItem` now carries `colorHex`;
  `AgendaSnapshot` carries `completedToday` / `totalToday` / `focusMinutesToday` / `topHabit`
  (`HabitSummary`). Decode-safe (an older snapshot still loads). Unit-tested (round-trip + legacy).
- **`App/AppServices.publishAgenda()`** — populates all of the above (list colors, today's progress,
  focus minutes, top-streak habit + its 7-day bits) and calls `WidgetCenter.reloadAllTimelines()`.
- **`App/Features/Intents/TaskIntents.swift`** — `CompleteTaskIntent` etc., already working from
  Shortcuts/Siri.

## Remaining integration (needs Xcode + a signed device)

1. **Add a Widget Extension target** to `DoIT.xcodeproj` (e.g. `DoITWidget`); add the `Widget/*.swift`
   files to it, with `SyncCore` + `DesignSystem` as dependencies. The `@main` is `DoITWidgetBundle`
   (in `DoITWidgetSuite.swift`); `NSSupportsLiveActivities = YES` in the app Info.plist for the LAs.
2. **App Groups capability** (`group.app.doit`) on **both** targets — needs a real bundle id +
   provisioning. Until then the app falls back to the per-process default store (the simulator warning).
3. **Share the intents/models with the widget target** (`CompleteTaskIntent` touches the app's
   `@Model`s + `PersistenceContainer`) — move the `@Model`s into a shared framework, or give the intent
   files membership in both targets.
4. **Wire the small app-side hooks** the new interactions raise (read on foreground):
   - `doit.pendingQuickAdd` (Bool) → present Quick Add.
   - `doit.focusControl` (`"toggle:<id>"` / `"stop:<id>"`) → `FocusController` pause/resume/stop, then
     `Activity.update/end` the Focus Live Activity.
5. **Sign + run on a device** — widget rendering, App Groups, and Live Activities all require signing.

## Known follow-up: widget-driven edits + sync

`CompleteTaskIntent` toggles the task in the shared store. The durable outbox now persists
(`OutboxPersistenceStore`), but the intent runs in the widget process — for a widget edit to flush
without the app, the intent should append to that shared outbox file directly (today it relies on the
app's next foreground sync to pick up the SwiftData change).
