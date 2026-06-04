import SwiftUI

/// App settings (P3-7 wiring). Currently: calendar write-back (mirror DoIT's scheduled blocks into
/// Apple Calendar) + a notification-permission entry point. The toggle is read on launch to run the
/// export after each sync (see `DoITApp`).
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services

    /// Persisted preference; read on launch to decide whether to export after sync.
    @AppStorage("calendarWriteBackEnabled") private var calendarWriteBack = false

    @State private var exporting = false
    @State private var lastExport: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Mirror scheduled blocks to Calendar", isOn: $calendarWriteBack)
                    Button {
                        Task { await exportNow() }
                    } label: {
                        HStack {
                            Label("Export today's blocks now", systemImage: "calendar.badge.plus")
                            Spacer()
                            if exporting { ProgressView() }
                        }
                    }
                    .disabled(exporting)
                    if let lastExport {
                        Text(lastExport).font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Calendar")
                } footer: {
                    Text("DoIT creates calendar events for your scheduled blocks so they show in Apple Calendar. Needs calendar access.")
                }

                Section {
                    Button("Enable reminders & alarms") {
                        Task { await services.requestNotificationAuthorization() }
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Reminders and routine alarm chains deliver as notifications. Time-Sensitive alerts break through Focus when you allow them; a louder Critical alert needs a special Apple entitlement.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func exportNow() async {
        exporting = true
        let result = await services.exportToCalendar()
        exporting = false
        lastExport = "Exported — \(result.created) created, \(result.updated) updated, \(result.deleted) removed."
    }
}
