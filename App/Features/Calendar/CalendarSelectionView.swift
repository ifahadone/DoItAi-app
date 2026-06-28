import SwiftUI
import DesignSystem

/// Choose which calendars contribute to DoIT's free/busy overlay (journey G05-S09). Everything is read
/// on-device via EventKit — calendar contents never leave the phone (US-PLAN-050). An empty selection
/// means *all* calendars are used (the privacy-preserving default that needs no configuration).
struct CalendarSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services

    @State private var calendars: [CalendarInfo] = []
    @State private var selected: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if calendars.isEmpty {
                        Text("No calendars available. Connect your calendar in Plan first.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(calendars) { cal in
                        Button {
                            if selected.contains(cal.id) { selected.remove(cal.id) } else { selected.insert(cal.id) }
                        } label: {
                            HStack(spacing: 12) {
                                Circle().fill(color(cal)).frame(width: 12, height: 12)
                                Text(cal.title).foregroundStyle(.primary)
                                Spacer(minLength: 8)
                                if isOn(cal) { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                        }
                    }
                } footer: {
                    Text("Selected calendars show as busy time on the dial and planner. With none selected, all your calendars are used. Calendar contents stay on your device.")
                }
            }
            .navigationTitle("Calendars")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { services.calendar.selectedCalendarIdentifiers = selected; dismiss() }
                }
            }
            .task {
                calendars = services.calendar.availableCalendars()
                selected = services.calendar.selectedCalendarIdentifiers
            }
        }
    }

    /// A calendar counts as "on" when explicitly selected, or when nothing is selected (all = default).
    private func isOn(_ cal: CalendarInfo) -> Bool { selected.isEmpty || selected.contains(cal.id) }
    private func color(_ cal: CalendarInfo) -> Color { cal.colorHex.flatMap { Color(hex: $0) } ?? .blue }
}
