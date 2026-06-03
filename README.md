# DoIT — iOS app (Phase 0 foundation)

The iOS client for **DoIT**, a standalone, AI-native productivity app (iOS 17+, Swift/SwiftUI,
offline-first). This repo is the **Phase 0 walking skeleton** (DevelopmentPlan §4): the pieces that
prove the loop *sign in → create a task offline → sync → pull on another device*, with no real
features yet.

Pairs with the specs in the sibling folders:
- `../DoIT-AppSpec.md` — product & engineering spec (data model §6, architecture §7, sync §8).
- `../DoIT-DevelopmentPlan.md` — phased plan (Phase 0 = §4).
- `../DoItAi-api/DoIT-ApiSpec.md` — the backend contract this client mirrors (§5 schema, §6 sync).

> **Why packages + loose app files (not a committed `.xcodeproj`)?** The reusable, framework-free
> logic ships as Swift Package Manager packages that build and test on their own. The app *target*
> (which needs SwiftData, SwiftUI, AuthenticationServices, and capabilities) is best generated in
> Xcode by you and pointed at the source under `App/` and the local packages. See
> [Create the Xcode app target](#create-the-xcode-app-target).

---

## Layout

```
DoItAi-app/
├─ SyncCore/                      # SPM package — PURE core, Foundation only (no SwiftUI/SwiftData)
│  ├─ Package.swift
│  ├─ Sources/SyncCore/
│  │  ├─ DTOs/                    # Codable wire DTOs mirroring DoIT-ApiSpec.md §5/§6 field-for-field
│  │  │  ├─ Enums.swift           #   TaskStatus / Priority / Energy (integer-backed), SyncOp, …
│  │  │  ├─ TaskDTO.swift  TaskListDTO.swift  TagDTO.swift
│  │  │  ├─ RecurrenceRule.swift  GeoPoint.swift
│  │  │  └─ SyncDTOs.swift        #   push op/result, pull change/response envelopes
│  │  ├─ Sync/
│  │  │  ├─ OutboxOp.swift        #   durable outbox entry (opId/entityType/…/fields)
│  │  │  ├─ ConflictResolver.swift#   pure row-level + field-level LWW (mirrors server, ApiSpec §6.1)
│  │  │  ├─ SyncTransport.swift   #   network boundary protocol (app's APIClient conforms)
│  │  │  └─ SyncEngine.swift      #   protocol + `DefaultSyncEngine` actor (enqueue/flush/applyPull)
│  │  └─ Support/
│  │     ├─ Clock.swift           #   Clock protocol + SystemClock / FixedClock / MutableClock
│  │     ├─ AnyCodable.swift      #   type-erased JSON value for the field bag
│  │     ├─ JSONCoding.swift      #   RFC 3339 UTC encoder/decoder
│  │     └─ Identifiers.swift     #   client UUID id generator
│  └─ Tests/SyncCoreTests/        # 41 unit tests (Clock, DTO round-trips, conflicts, engine)
│
├─ DesignSystem/                  # SPM package (SwiftUI) — minimal Theme tokens
│  ├─ Package.swift
│  └─ Sources/DesignSystem/       # Theme (semantic colors + 4-pt spacing + radii) via Environment
│
├─ App/                           # App-TARGET source (needs the Xcode app target; see below)
│  ├─ DoITApp.swift               # @main App + 5-tab shell (Today/Plan/+/Lists/Insights) + auth gate
│  ├─ AppConfig.swift             # App Group id, bundle id, API base URL (placeholders)
│  ├─ AppServices.swift           # DI container: Clock, SyncEngine, APIClient, AuthService
│  ├─ Persistence/
│  │  ├─ Models.swift             # SwiftData @Model TaskModel / TaskListModel / TagModel
│  │  ├─ Models+DTO.swift         # typed accessors + DTO <-> @Model conversion
│  │  ├─ ModelContainer.swift     # App Group SwiftData container (group.app.doit — placeholder)
│  │  └─ SwiftDataSyncStore.swift # applies pulled deltas into SwiftData (SyncCore.SyncStore)
│  ├─ Networking/
│  │  ├─ APIClient.swift          # actor: signInWithApple / refresh / syncPush / syncPull (URLSession)
│  │  └─ AuthDTOs.swift           # /auth/* request/response shapes + error envelope
│  ├─ Auth/
│  │  ├─ AuthService.swift        # Sign in with Apple (AuthenticationServices) + token orchestration
│  │  ├─ KeychainStore.swift      # Keychain wrapper for access/refresh tokens
│  │  └─ SignInView.swift         # sign-in gate UI
│  └─ Features/Today/
│     ├─ TodayView.swift          # lists tasks from SwiftData; + button creates one
│     └─ TaskCreation.swift       # local create + enqueue to the outbox
│
├─ .gitignore
└─ README.md
```

### What compiles today vs what needs the Xcode target

| Part | Status |
| --- | --- |
| `SyncCore` package | **Builds & tests via `swift build` / `swift test`.** 41 unit tests pass. Foundation only. |
| `DesignSystem` package | **Builds via `swift build`** (cross-platform; compiles on macOS for dev). |
| Everything under `App/` | **Requires the Xcode app target** (SwiftData, SwiftUI, AuthenticationServices, App Group). Will *not* compile standalone with `swift build` — that's expected for Phase 0. |

---

## Run the SyncCore tests

`SyncCore` is dependency-free, so it resolves and runs fully offline:

```sh
cd SyncCore
swift build        # compile the pure core
swift test         # run all unit tests (Clock, DTO Codable round-trips, LWW conflict, engine)
```

`DesignSystem` builds the same way (`cd DesignSystem && swift build`).

---

## Create the Xcode app target

The packages above are reusable; the app itself is an Xcode target you create once.

1. **New project.** Xcode → *File ▸ New ▸ Project… ▸ iOS ▸ App*.
   - Product Name: `DoIT` · Interface: **SwiftUI** · Language: **Swift** · Storage: **None** (we wire
     SwiftData ourselves) · Minimum Deployment: **iOS 17.0**.
   - Set the **Bundle Identifier** to your real id and update `AppConfig.bundleIdentifier` to match.
   - Save it *inside this repo* (e.g. at the repo root). Delete the template's generated
     `ContentView.swift` / `<App>.swift` so they don't clash with `App/DoITApp.swift`.

2. **Add the app sources.** Drag the `App/` folder into the project navigator (Add to target: the app
   target; *Create groups*). These files reference `SyncCore` and `DesignSystem`.

3. **Add the local packages.** *File ▸ Add Package Dependencies… ▸ Add Local…* and add both
   `SyncCore` and `DesignSystem` folders. Then, in the app target's *General ▸ Frameworks, Libraries,
   and Embedded Content*, add the `SyncCore` and `DesignSystem` library products.

4. **Capabilities** (Signing & Capabilities tab — see the next section for the exact values).
   Add **App Groups** and **Sign in with Apple**.

5. **Build & run** on an iOS 17+ simulator. Until the backend is reachable, sign-in and sync calls
   will fail gracefully; the Today tab still creates tasks offline (they show "Pending sync").

> Optional: if you later prefer a generated, reproducible project, introduce
> [XcodeGen](https://github.com/yonaskolb/XcodeGen) or
> [Tuist](https://tuist.io) with a manifest that references `App/` and the two packages. Not included
> here to avoid adding a dependency in Phase 0.

---

## Capabilities & credentials you must set up

These cannot be committed — configure them on your target / Apple Developer account:

| What | Where | Value / notes |
| --- | --- | --- |
| **App Group** | Target ▸ Signing & Capabilities ▸ *App Groups* | Add a group id and set `AppConfig.appGroupIdentifier` to it. The code uses **`group.app.doit`** as a **placeholder** — replace with `group.<your-bundle-id>` (must be registered on your provisioning profile). The same group must be enabled on the future Widget target so they share the SwiftData store (AppSpec §7, §9). Without it, `ModelContainer` falls back to a non-shared store and logs a warning in DEBUG. |
| **Sign in with Apple** | Target ▸ Signing & Capabilities ▸ *Sign in with Apple*; plus enable the capability for your App ID in the Apple Developer portal | Required for `AuthService` (AppSpec §13, ApiSpec §4.1). The backend verifies the identity token's `aud` against your **bundle id**, so they must match. |
| **Bundle identifier** | Target ▸ General; mirror in `AppConfig.bundleIdentifier` | Used as the Sign in with Apple / APNs audience. |
| **API base URL** | `AppConfig.apiBaseURL` / Info.plist key `DOIT_API_BASE_URL` | Defaults to the placeholder `https://doit.app/api/v1` (ApiSpec §3). Point it at your deployed API or a local mock server (DevelopmentPlan Phase 0 task 0.2) per scheme. |
| **Keychain** | automatic | `KeychainStore` stores tokens with `…AfterFirstUnlockThisDeviceOnly`; no iCloud Keychain. If widgets need token access later, set a Keychain **access group** and pass it to `KeychainStore`. |

**Secrets that must never be in this repo or the app binary:** the Claude API key (backend only,
ApiSpec §9), APNs `.p8`, Apple service keys. Signing assets (`.mobileprovision`, `.p12`, `.p8`) are
git-ignored.

---

## Architecture notes (Phase 0)

- **Pure core first.** All sync/conflict/DTO logic lives in `SyncCore` with no Apple-UI frameworks,
  so it's unit-tested in isolation (AppSpec §7, §16). The app target adapts it to SwiftData
  (`SwiftDataSyncStore`) and URLSession (`APIClient` conforms to `SyncTransport`).
- **No `Date()` in logic.** Time is injected via the `Clock` protocol everywhere it matters
  (AppSpec §16) — `SystemClock` in the app, `FixedClock`/`MutableClock` in tests.
- **Offline-first outbox.** Local mutations write SwiftData immediately and enqueue an `OutboxOp`;
  `DefaultSyncEngine.flush` pushes them with client-minted `opId`s so retries are idempotent
  (AppSpec §8, ApiSpec §6.3).
- **Stubs are marked.** Intentionally-unimplemented logic (real reconciliation, backoff, paging,
  outbox persistence) carries `// TODO(Phase 1):` markers showing exactly what lands next.

---

## License

TBD.
