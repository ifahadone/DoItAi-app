import SwiftUI
import SyncCore

/// Full recurrence editor (journey G04-S11): frequency, interval ("every N"), weekly weekday
/// selection, and an end condition (never / on a date / after N occurrences). The backend stores an
/// RFC-5545 subset (``RecurrenceRule``) and the materializer already honours interval/byWeekday/
/// count/until — this surface just exposes them. Editing applies to this and all future occurrences;
/// "Edit this event only" (in Task Detail) detaches a single instance.
struct RecurrenceEditorView: View {
    @Environment(\.dismiss) private var dismiss

    private enum Ending: Hashable { case never, onDate, afterCount }

    @State private var freq: RecurrenceRule.Freq
    @State private var interval: Int
    @State private var weekdays: Set<Int>
    @State private var ending: Ending
    @State private var until: Date
    @State private var count: Int

    let onSave: (RecurrenceRule) -> Void

    init(initial: RecurrenceRule, onSave: @escaping (RecurrenceRule) -> Void) {
        _freq = State(initialValue: initial.freq)
        _interval = State(initialValue: max(1, initial.interval))
        _weekdays = State(initialValue: Set(initial.byWeekday ?? []))
        _until = State(initialValue: initial.until ?? Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date())
        _count = State(initialValue: initial.count ?? 10)
        if initial.until != nil { _ending = State(initialValue: .onDate) }
        else if initial.count != nil { _ending = State(initialValue: .afterCount) }
        else { _ending = State(initialValue: .never) }
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Frequency") {
                    Picker("Repeats", selection: $freq) {
                        Text("Daily").tag(RecurrenceRule.Freq.daily)
                        Text("Weekly").tag(RecurrenceRule.Freq.weekly)
                        Text("Monthly").tag(RecurrenceRule.Freq.monthly)
                        Text("Yearly").tag(RecurrenceRule.Freq.yearly)
                    }
                    Stepper("Every \(interval) \(unitLabel(interval))", value: $interval, in: 1...99)
                }

                if freq == .weekly {
                    Section {
                        weekdayPicker
                    } header: {
                        Text("On these days")
                    } footer: {
                        Text(weekdays.isEmpty ? "With no days picked, it repeats weekly on the task's own day." : "")
                    }
                }

                Section("Ends") {
                    Picker("Ends", selection: $ending) {
                        Text("Never").tag(Ending.never)
                        Text("On date").tag(Ending.onDate)
                        Text("After…").tag(Ending.afterCount)
                    }
                    .pickerStyle(.segmented)
                    if ending == .onDate {
                        DatePicker("End date", selection: $until, displayedComponents: .date)
                    } else if ending == .afterCount {
                        Stepper("After \(count) occurrence\(count == 1 ? "" : "s")", value: $count, in: 1...365)
                    }
                }

                Section {
                    Text(summary).font(.callout).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Repeat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onSave(buildRule()); dismiss() }
                }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private var weekdayPicker: some View {
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { weekday in
                let on = weekdays.contains(weekday)
                Button {
                    if on { weekdays.remove(weekday) } else { weekdays.insert(weekday) }
                } label: {
                    Text(Self.weekdaySymbol(weekday))
                        .font(.caption.weight(.medium))
                        .frame(width: 32, height: 32)
                        .background(on ? Color.accentColor : Color.secondary.opacity(0.15), in: Circle())
                        .foregroundStyle(on ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func buildRule() -> RecurrenceRule {
        RecurrenceRule(
            freq: freq,
            interval: max(1, interval),
            byWeekday: (freq == .weekly && !weekdays.isEmpty) ? weekdays.sorted() : nil,
            byMonthDay: nil,
            count: ending == .afterCount ? count : nil,
            until: ending == .onDate ? until : nil
        )
    }

    private func unitLabel(_ n: Int) -> String {
        let base: String
        switch freq {
        case .daily: base = "day"
        case .weekly: base = "week"
        case .monthly: base = "month"
        case .yearly: base = "year"
        }
        return n == 1 ? base : base + "s"
    }

    /// Plain-English description of the configured rule (so the user sees exactly what will happen).
    private var summary: String {
        var s = interval == 1 ? "Repeats \(freq.rawValue)" : "Every \(interval) \(unitLabel(interval))"
        if freq == .weekly, !weekdays.isEmpty {
            s += " on " + weekdays.sorted().map { Self.weekdayName($0) }.joined(separator: ", ")
        }
        switch ending {
        case .never: break
        case .onDate: s += ", until " + until.formatted(date: .abbreviated, time: .omitted)
        case .afterCount: s += ", for \(count) occurrence\(count == 1 ? "" : "s")"
        }
        return s + "."
    }

    private static func weekdaySymbol(_ weekday: Int) -> String {
        ["S", "M", "T", "W", "T", "F", "S"][(weekday - 1) % 7]
    }
    private static func weekdayName(_ weekday: Int) -> String {
        ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][(weekday - 1) % 7]
    }
}
