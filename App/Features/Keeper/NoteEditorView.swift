import SwiftUI
import SwiftData
import SyncCore

/// Edit a single note (Keeper — added feature; see DevelopmentPlan §10.5). Title + free-form body, with a pin toggle. Text edits are
/// committed on Done (each a no-op if unchanged) and flushed when live-syncing.
struct NoteEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services

    @Bindable var note: NoteModel

    @State private var titleDraft = ""
    @State private var bodyDraft = ""

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $titleDraft, axis: .vertical)
                    .font(.headline)
            }
            Section("Note") {
                TextEditor(text: $bodyDraft)
                    .frame(minHeight: 260)
                    .overlay(alignment: .topLeading) {
                        if bodyDraft.isEmpty {
                            Text("Write anything you want to keep…")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8).padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
            }
        }
        .navigationTitle("Note")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await togglePin() } } label: {
                    Image(systemName: note.pinned ? "pin.fill" : "pin")
                }
                .accessibilityLabel(note.pinned ? "Unpin note" : "Pin note")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { Task { await commit(); dismiss() } }
            }
        }
        .onAppear {
            titleDraft = note.title
            bodyDraft = note.body
        }
    }

    private var mutation: NoteMutation {
        NoteMutation(context: modelContext, engine: services.syncEngine, clock: services.clock,
                     idGenerator: services.idGenerator, ownerId: services.currentOwnerId)
    }

    private func commit() async {
        await mutation.setTitle(note, titleDraft)
        await mutation.setBody(note, bodyDraft)
        await syncIfLive()
    }

    private func togglePin() async {
        await mutation.setPinned(note, !note.pinned)
        await syncIfLive()
    }

    private func syncIfLive() async { if AppConfig.isLiveSync { await services.syncOnce() } }
}
