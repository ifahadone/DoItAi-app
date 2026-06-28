import SwiftUI
import SwiftData
import SyncCore
import DesignSystem

/// Create/edit a routine or habit (AppSpec §5.2, DevelopmentPlan P3-4): name, ordered steps with
/// durations, chain mode, anchor time, weekday recurrence, and (habits) grace days.
struct RoutineBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthService.self) private var auth
    @Environment(AppServices.self) private var services

    let routine: RoutineModel?
    let isHabit: Bool

    @State private var name = ""
    @State private var steps: [RoutineStep] = []
    @State private var chained = false
    @State private var anchorEnabled = false
    @State private var anchorDate = Date()
    @State private var weekdays: Set<Int> = [] // 1=Sun…7=Sat; empty = every day
    @State private var graceDays = 0
    /// Smart wake (FR-ALRM-090): a first-commitment time the suggested wake works back from.
    @State private var wakeEnabled = false
    @State private var firstCommitment = Date()

    /// Total duration of the routine's steps, in minutes.
    private var totalStepMinutes: Int { steps.reduce(0) { $0 + max(0, $1.minutes) } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(isHabit ? "Habit name" : "Routine name", text: $name)
                }

                if !isHabit {
                    Section {
                        ForEach(steps.indices, id: \.self) { index in
                            HStack {
                                TextField("Step", text: $steps[index].title)
                                Spacer()
                                Button {
                                    steps[index].hasAlarm.toggle()
                                } label: {
                                    Image(systemName: steps[index].hasAlarm ? "bell.fill" : "bell.slash")
                                        .foregroundStyle(steps[index].hasAlarm ? Color.accentColor : .secondary)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel(steps[index].hasAlarm ? "Alarm on" : "Alarm off")
                                Stepper("\(steps[index].minutes)m", value: $steps[index].minutes, in: 0...600, step: 5)
                                    .fixedSize()
                            }
                        }
                        .onDelete { steps.remove(atOffsets: $0) }
                        .onMove { steps.move(fromOffsets: $0, toOffset: $1) }
                        Button { steps.append(RoutineStep(title: "", minutes: 15, ord: steps.count)) } label: {
                            Label("Add step", systemImage: "plus")
                        }
                    } header: {
                        Text("Steps")
                    } footer: {
                        Text("Tap the bell on a step to get a Time-Sensitive alarm when it begins.")
                    }
                    Section("Schedule") {
                        Toggle("Chain steps (auto-start next)", isOn: $chained)
                        Toggle("Anchor start time", isOn: $anchorEnabled)
                        if anchorEnabled {
                            DatePicker("Starts at", selection: $anchorDate, displayedComponents: .hourAndMinute)
                        }
                        weekdayPicker
                    }
                    Section {
                        Toggle("Suggest a wake time", isOn: $wakeEnabled)
                        if wakeEnabled {
                            DatePicker("First commitment", selection: $firstCommitment, displayedComponents: .hourAndMinute)
                            if let wake = SmartWakePlanner.suggestedWake(before: firstCommitment, routineMinutes: totalStepMinutes) {
                                LabeledContent("Wake by", value: wake.formatted(date: .omitted, time: .shortened))
                            }
                        }
                    } header: {
                        Text("Smart wake")
                    } footer: {
                        Text("Wake just early enough to finish this \(totalStepMinutes)-min routine (plus a 10-min buffer) before your first commitment.")
                    }
                } else {
                    Section("Schedule") {
                        weekdayPicker
                        Stepper("Grace days: \(graceDays)", value: $graceDays, in: 0...7)
                    }
                }
                previewSection
            }
            .navigationTitle(routine == nil ? (isHabit ? "New Habit" : "New Routine") : "Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if !isHabit { ToolbarItem(placement: .topBarLeading) { EditButton() } }
            }
            .onAppear(perform: load)
        }
    }

    /// The next few dates this routine/habit will materialize on, given the chosen weekdays + anchor —
    /// a preview so recurrence mistakes are caught before saving (US-ROUT-020, journey G07-S10).
    private var upcomingRuns: [Date] {
        let cal = Calendar.current
        let now = services.clock.now()
        var results: [Date] = []
        var day = cal.startOfDay(for: now)
        var guardCount = 0
        while results.count < 5 && guardCount < 90 {
            guardCount += 1
            let weekday = cal.component(.weekday, from: day)
            if weekdays.isEmpty || weekdays.contains(weekday) {
                var d = day
                if anchorEnabled && !isHabit {
                    let c = cal.dateComponents([.hour, .minute], from: anchorDate)
                    d = cal.date(bySettingHour: c.hour ?? 0, minute: c.minute ?? 0, second: 0, of: day) ?? day
                }
                results.append(d)
            }
            day = cal.date(byAdding: .day, value: 1, to: day) ?? day
        }
        return results
    }

    @ViewBuilder private var previewSection: some View {
        Section {
            ForEach(upcomingRuns, id: \.self) { date in
                HStack(spacing: 10) {
                    Image(systemName: "calendar").foregroundStyle(.secondary)
                    Text(date.formatted(date: .abbreviated, time: (anchorEnabled && !isHabit) ? .shortened : .omitted))
                        .font(.subheadline)
                    if Calendar.current.isDateInToday(date) {
                        Text("Today").font(.caption2.weight(.semibold)).foregroundStyle(.tint)
                    }
                }
            }
        } header: {
            Text("Next runs")
        } footer: {
            Text(weekdays.isEmpty ? "Repeats every day." : "Repeats on the selected days.")
        }
    }

    private var weekdayPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Repeat").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(1...7, id: \.self) { weekday in
                    let on = weekdays.contains(weekday)
                    Button {
                        if on { weekdays.remove(weekday) } else { weekdays.insert(weekday) }
                    } label: {
                        Text(Self.weekdaySymbol(weekday))
                            .font(.caption.weight(.medium))
                            .frame(width: 30, height: 30)
                            .background(on ? Color.accentColor : Color.secondary.opacity(0.15), in: Circle())
                            .foregroundStyle(on ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(weekdays.isEmpty ? "Every day" : "Selected days").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private static func weekdaySymbol(_ weekday: Int) -> String {
        ["S", "M", "T", "W", "T", "F", "S"][(weekday - 1) % 7]
    }

    private func load() {
        guard let routine else { return }
        name = routine.name
        steps = routine.steps.sorted { $0.ord < $1.ord }
        chained = routine.chained
        graceDays = routine.graceDays
        weekdays = Set(routine.recurrence?.weekdays ?? [])
        if let anchor = routine.anchorTime, let minute = RoutineMaterializer.parseAnchorMinute(anchor) {
            anchorEnabled = true
            anchorDate = Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date()
        }
    }

    private func save() async {
        let recurrence: RoutineRecurrence? = weekdays.isEmpty ? nil : RoutineRecurrence(weekdays: weekdays.sorted())
        let anchorTime: String? = (anchorEnabled && !isHabit) ? hhmm(anchorDate) : nil
        let ordered = steps.enumerated().map { index, step in
            RoutineStep(title: step.title, minutes: step.minutes, ord: index, hasAlarm: step.hasAlarm)
        }
        let mutation = RoutineMutation(context: modelContext, engine: services.syncEngine, apiClient: services.apiClient,
                                       clock: services.clock, idGenerator: services.idGenerator, ownerId: ownerId)
        if let routine {
            await mutation.update(routine, name: name, anchorTime: anchorTime, recurrence: recurrence,
                                  chained: chained, graceDays: graceDays, steps: ordered)
        } else {
            await mutation.create(name: name, isHabit: isHabit, steps: ordered, anchorTime: anchorTime,
                                  recurrence: recurrence, chained: chained, graceDays: graceDays)
        }
        if AppConfig.isLiveSync { await services.syncOnce() }
        dismiss()
    }

    private func hhmm(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    private var ownerId: String {
        if case let .signedIn(userId) = auth.state, let userId { return userId }
        return "local-user"
    }
}
