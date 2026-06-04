import SwiftUI

/// App settings (P3-7 wiring). Currently: calendar write-back (mirror DoIT's scheduled blocks into
/// Apple Calendar) + a notification-permission entry point. The toggle is read on launch to run the
/// export after each sync (see `DoITApp`).
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services

    /// Persisted preference; read on launch to decide whether to export after sync.
    @AppStorage("calendarWriteBackEnabled") private var calendarWriteBack = false
    /// AI opt-in (ApiSpec §9.6). Mirrors `users.ai_consent` on the server; the AI features no-op when off.
    @AppStorage("aiConsentEnabled") private var aiConsent = false

    @State private var exporting = false
    @State private var lastExport: String?
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button { showPaywall = true } label: {
                        HStack {
                            Label(services.entitlements.isPro ? "DoIT Pro" : "Upgrade to DoIT Pro", systemImage: "crown.fill")
                            Spacer()
                            if services.entitlements.isPro {
                                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                            } else {
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    }
                } footer: {
                    Text(services.entitlements.isPro
                         ? "Thanks for supporting DoIT. All Pro features are unlocked."
                         : "Unlock the sectograph, AI, calendar write-back, analytics, unlimited routines, and sharing.")
                }

                Section {
                    Toggle("Enable the AI assistant", isOn: $aiConsent)
                } header: {
                    Text("AI Assistant")
                } footer: {
                    Text("The AI parses your quick-add, auto-plans your day, and writes briefs & reviews — via the secure backend (your data is never used for training). With it off, DoIT uses on-device parsing and rules-based planning only.")
                }
                .onChange(of: aiConsent) { _, on in Task { await services.setAiConsent(on) } }

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
            .sheet(isPresented: $showPaywall) {
                PaywallView().environment(services)
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
