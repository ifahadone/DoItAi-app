import SwiftUI
import SwiftData
import SyncCore
import DesignSystem

/// Routines + habits management (AppSpec §5.2, DevelopmentPlan P3-4). Lists step-routines and tracked
/// habits, opens the builder to create/edit, materializes today's routines into the plan, and logs
/// habit completions (server-authoritative streak).
struct RoutinesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.theme) private var theme
    @Environment(AuthService.self) private var auth
    @Environment(AppServices.self) private var services

    @Query(filter: #Predicate<RoutineModel> { $0.deletedAt == nil }, sort: \RoutineModel.name)
    private var routines: [RoutineModel]

    @State private var editing: RoutineModel?
    @State private var creatingHabit = false
    @State private var showBuilder = false
    @State private var materializedNote: String?

    private var templates: [RoutineModel] { routines.filter { !$0.isHabit } }
    private var habits: [RoutineModel] { routines.filter { $0.isHabit } }

    var body: some View {
        List {
            Section {
                Button {
                    Task {
                        let count = await services.materializeRoutines()
                        if AppConfig.isLiveSync { await services.syncOnce() }
                        materializedNote = count > 0 ? "Added \(count) blocks to today" : "Nothing to materialize"
                    }
                } label: {
                    Label("Materialize today", systemImage: "wand.and.stars")
                }
                if let note = materializedNote {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Routines") {
                if templates.isEmpty { Text("No routines yet.").font(.subheadline).foregroundStyle(.secondary) }
                ForEach(templates) { routine in
                    Button { editing = routine } label: { routineRow(routine) }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { Task { await delete(routine) } } label: { Label("Delete", systemImage: "trash") }
                            Button { Task { await mutation.duplicate(routine) } } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                                .tint(.indigo)
                        }
                        .swipeActions(edge: .leading) {
                            Button { Task { await mutation.setPaused(routine, !routine.paused) } } label: {
                                Label(routine.paused ? "Resume" : "Pause", systemImage: routine.paused ? "play.fill" : "pause.fill")
                            }.tint(.orange)
                            Button { Task { await mutation.setArchived(routine, !routine.archived) } } label: {
                                Label(routine.archived ? "Unarchive" : "Archive", systemImage: "archivebox")
                            }.tint(.gray)
                        }
                }
            }

            Section("Habits") {
                if habits.isEmpty { Text("No habits yet.").font(.subheadline).foregroundStyle(.secondary) }
                ForEach(habits) { habit in
                    habitRow(habit)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { Task { await delete(habit) } } label: { Label("Delete", systemImage: "trash") }
                        }
                }
            }
        }
        .navigationTitle("Routines")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { editing = nil; creatingHabit = false; showBuilder = true } label: { Label("New Routine", systemImage: "list.bullet.indent") }
                    Button { editing = nil; creatingHabit = true; showBuilder = true } label: { Label("New Habit", systemImage: "flame") }
                } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showBuilder) {
            RoutineBuilderView(routine: nil, isHabit: creatingHabit).environment(auth).environment(services)
        }
        .sheet(item: $editing) { routine in
            RoutineBuilderView(routine: routine, isHabit: routine.isHabit).environment(auth).environment(services)
        }
    }

    private func routineRow(_ routine: RoutineModel) -> some View {
        HStack(spacing: theme.spacing.md) {
            Image(systemName: "list.bullet.indent").foregroundStyle(Color(hex: routine.colorHex) ?? theme.colors.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(routine.name.isEmpty ? "Untitled routine" : routine.name)
                    .foregroundStyle(routine.archived ? .secondary : .primary)
                Text("\(routine.steps.count) steps\(routine.anchorTime.map { " · \($0)" } ?? "")\(routineStateSuffix(routine))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if routine.paused { Image(systemName: "pause.circle.fill").foregroundStyle(.orange) }
            if routine.archived { Image(systemName: "archivebox.fill").foregroundStyle(.gray) }
        }
        .opacity(routine.archived ? 0.6 : 1)
    }

    private func routineStateSuffix(_ r: RoutineModel) -> String {
        if r.archived { return " · Archived" }
        if r.paused { return " · Paused" }
        return ""
    }

    private func habitRow(_ habit: RoutineModel) -> some View {
        HStack(spacing: theme.spacing.md) {
            Image(systemName: "flame.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(habit.name.isEmpty ? "Untitled habit" : habit.name)
                Text("🔥 \(habit.streakCurrent) · best \(habit.streakLongest)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done") { Task { await logHabit(habit) } }
                .buttonStyle(.bordered).controlSize(.small)
        }
    }

    private var mutation: RoutineMutation {
        RoutineMutation(context: modelContext, engine: services.syncEngine, apiClient: services.apiClient,
                        clock: services.clock, idGenerator: services.idGenerator, ownerId: ownerId)
    }
    private var ownerId: String {
        if case let .signedIn(userId) = auth.state, let userId { return userId }
        return "local-user"
    }
    private func delete(_ routine: RoutineModel) async {
        await mutation.delete(routine)
        if AppConfig.isLiveSync { await services.syncOnce() }
    }
    private func logHabit(_ habit: RoutineModel) async {
        _ = await mutation.logHabitToday(habit)
    }
}
