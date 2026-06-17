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

## Remaining integration (needs Xcode GUI + the **paid** Apple Developer Program)

> ⚠️ App Groups **and** Live Activities entitlements require a **paid** Apple Developer Program
> membership ($99/yr). A *free* personal team can device-install the app but **cannot** enable either,
> so the widget/Live-Activity suite cannot run until enrollment. Add the target via the **Xcode GUI**
> (File → New → Target → Widget Extension) — do **not** hand-edit `project.pbxproj` to add a target.

Exact runbook once enrolled:

1. **Add a Widget Extension target** in Xcode (File → New → Target → **Widget Extension**, name
   `DoITWidget`, "Include Live Activity" ON). Delete its generated sample files. Add the existing
   `Widget/*.swift` to the target's membership; add `SyncCore` + `DesignSystem` as its package
   dependencies. The bundle's `@main` is `DoITWidgetBundle` (in `DoITWidgetSuite.swift`).
2. **App Groups** (`group.app.doit`) capability on **both** the `DoIT` app target and `DoITWidget`
   (Signing & Capabilities → + Capability → App Groups). Until then the app uses the per-process default
   store (harmless — the foreground hooks below just find nothing).
3. **Live Activities**: add `NSSupportsLiveActivities = YES` to the app target (Info tab, or
   `INFOPLIST_KEY_NSSupportsLiveActivities = YES` build setting).
4. **Share the intents/models with the widget target** — `CompleteTaskIntent` touches the app's
   `@Model`s + `PersistenceContainer`; give the intent files membership in both targets (or move the
   `@Model`s to a shared framework).
5. **Sign both targets** with your paid team; run on a device.

### App-side hooks — ✅ DONE (in code now)

`DoITApp.RootTabView` already drains the App-Group commands on foreground
(`processWidgetControls()` / `handleFocusControl(_:)`): `doit.pendingQuickAdd` → presents Quick Add;
`doit.focusControl` (`toggle:`/`stop:`) → `FocusController` pause/resume/stop (+ logs actual minutes,
syncs). These are wired and build today; they simply no-op until the App Group entitlement (step 2)
makes the shared store real. The remaining LA-side `Activity.update/end` calls live in the extension
(steps 1–5).

## Known follow-up: widget-driven edits + sync

`CompleteTaskIntent` toggles the task in the shared store. The durable outbox now persists
(`OutboxPersistenceStore`), but the intent runs in the widget process — for a widget edit to flush
without the app, the intent should append to that shared outbox file directly (today it relies on the
app's next foreground sync to pick up the SwiftData change).
