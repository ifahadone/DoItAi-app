import SwiftUI
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif
import DesignSystem

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
    /// The Today sectograph style (P5-5). Read by ``TodayView`` via the same key.
    @AppStorage("dialStyle") private var dialStyleRaw = DialStyle.arc.rawValue

    @State private var exporting = false
    @State private var lastExport: String?
    @State private var showPaywall = false
    @State private var preparingExport = false
    @State private var exportURL: URL?
    @State private var showDeleteConfirm = false
    @State private var notifStatus: UNAuthorizationStatus = .notDetermined
    @Environment(\.openURL) private var openURL
    @AppStorage("quietHoursEnabled") private var quietHoursEnabled = false
    @AppStorage("quietHoursStart") private var quietStart = 1320 // 22:00
    @AppStorage("quietHoursEnd") private var quietEnd = 420      // 07:00

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
                    NavigationLink {
                        DialStylePicker()
                    } label: {
                        HStack {
                            Label("Day-dial style", systemImage: "circle.dotted")
                            Spacer()
                            Text(DialStyle(rawValue: dialStyleRaw)?.title ?? "Arc")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Day dial")
                } footer: {
                    Text("Choose how the sectograph renders today's blocks — tap the dial on Today to switch, too.")
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
                    if notifStatus == .denied {
                        Button {
                            #if canImport(UIKit)
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                            #endif
                        } label: {
                            Label("Notifications are off — open iOS Settings", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    } else if notifStatus == .notDetermined {
                        // First-run value prompt before the one-shot iOS dialog (G13 / G16 permission).
                        PermissionCard(
                            icon: "bell.badge",
                            title: "Turn on reminders & alarms",
                            message: "Get nudged for due tasks and routine steps. Time-Sensitive alerts can break through Focus.",
                            actionTitle: "Enable"
                        ) {
                            Task { await services.requestNotificationAuthorization(); await refreshNotifStatus() }
                        }
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                    } else {
                        Label("Reminders are on", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    Button {
                        Task { await NotificationScheduler().scheduleTest() }
                    } label: {
                        Label("Send a test notification", systemImage: "bell.badge")
                    }
                    // Honest explanation of iOS alarm limits (journey G13-S11).
                    DisclosureGroup {
                        Text(AlarmScheduler.onboardingNote)
                            .font(.caption).foregroundStyle(.secondary)
                    } label: {
                        Label("Why an alarm might not ring", systemImage: "questionmark.circle")
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Reminders and routine alarm chains deliver as notifications. Time-Sensitive alerts break through Focus when you allow them; a louder Critical alert needs a special Apple entitlement.")
                }

                Section {
                    Toggle("Quiet hours", isOn: $quietHoursEnabled)
                    if quietHoursEnabled {
                        DatePicker("From", selection: timeBinding($quietStart), displayedComponents: .hourAndMinute)
                        DatePicker("To", selection: timeBinding($quietEnd), displayedComponents: .hourAndMinute)
                    }
                } header: {
                    Text("Quiet hours")
                } footer: {
                    Text("During quiet hours, reminders arrive silently (no sound, delivered to Notification Center) so they don't interrupt you.")
                }

                Section {
                    if services.auth.isLocalMode {
                        // Local-first user: offer the upgrade-to-cloud path (G01-S04 promise, US-ONB-020).
                        Button {
                            Task { await services.auth.signInWithApple() }
                        } label: {
                            HStack {
                                Label("Sign in with Apple to sync", systemImage: "applelogo")
                                Spacer()
                                if services.auth.isSigningIn { ProgressView() }
                            }
                        }
                        .disabled(services.auth.isSigningIn)
                    } else {
                        if let exportURL {
                            ShareLink("Share your data export", item: exportURL)
                        } else {
                            Button {
                                Task { preparingExport = true; exportURL = await prepareExport(); preparingExport = false }
                            } label: {
                                HStack {
                                    Label("Export my data", systemImage: "square.and.arrow.up")
                                    Spacer()
                                    if preparingExport { ProgressView() }
                                }
                            }
                            .disabled(preparingExport)
                        }
                        Button(role: .destructive) { showDeleteConfirm = true } label: {
                            Label("Delete account", systemImage: "trash")
                        }
                    }
                } header: {
                    Text("Account")
                } footer: {
                    Text(services.auth.isLocalMode
                         ? "You're using DoIT on this device only. Sign in with Apple to back up and sync across your devices — your local data is kept."
                         : "Export downloads all your data as JSON. Deleting your account permanently erases everything on the server and cannot be undone.")
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView().environment(services)
            }
            .confirmationDialog("Permanently delete your account and all data?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) { Task { await deleteAccount() } }
                Button("Cancel", role: .cancel) {}
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await refreshNotifStatus() }
        }
    }

    private func refreshNotifStatus() async {
        notifStatus = await NotificationScheduler().authorizationStatus()
    }

    /// Bridge a minute-of-day @AppStorage Int to a `DatePicker`'s `Date` (hour+minute only).
    private func timeBinding(_ store: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: store.wrappedValue / 60,
                                      minute: store.wrappedValue % 60, second: 0, of: Date()) ?? Date()
            },
            set: { newValue in
                let c = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                store.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        )
    }

    private func exportNow() async {
        exporting = true
        let result = await services.exportToCalendar()
        exporting = false
        lastExport = "Exported — \(result.created) created, \(result.updated) updated, \(result.deleted) removed."
    }

    /// Fetch the account export JSON and write it to a temp file for the share sheet (P6-5).
    private func prepareExport() async -> URL? {
        guard let data = try? await services.apiClient.exportAccountData() else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("doit-export.json")
        try? data.write(to: url, options: .atomic)
        return url
    }

    /// Permanently delete the account, then sign out (the account no longer exists).
    private func deleteAccount() async {
        try? await services.apiClient.deleteAccount()
        services.auth.signOut()
        dismiss()
    }
}
