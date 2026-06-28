import SwiftUI
import SyncCore
import DesignSystem

/// Share a list with other people (DevelopmentPlan P5-5, AppSpec §16). Reached from the list's toolbar
/// (Pro-gated at the call site). On appear it ensures a share exists for the list and loads the member
/// roster; the owner can mint role-scoped invite codes and manage members, and anyone can redeem a code
/// to join — after which a pull backfills the shared list + its tasks.
///
/// **Account-bound:** every control hits the live API and needs a signed-in session. In offline/demo
/// builds the calls fail quietly and the roster stays empty (the screen degrades to inert, not broken).
struct SharingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services
    let list: TaskListModel

    @State private var share: ShareDTO?
    @State private var members: [ShareMemberDTO] = []
    @State private var inviteRole = "editor"
    @State private var lastInvite: InviteDTO?
    @State private var joinCode = ""
    @State private var busy = false
    @State private var status: String?

    private var apiClient: APIClient { services.apiClient }
    private var myUserId: String { services.currentOwnerId }
    private var isOwner: Bool { share.map { $0.ownerId == myUserId } ?? true }
    /// This user's role on the shared list, driving role-aware controls (journey G09 role variants).
    private var myRole: String { members.first { $0.userId == myUserId }?.role ?? (isOwner ? "owner" : "member") }

    private static let roles = ["editor", "commenter", "viewer"]

    var body: some View {
        NavigationStack {
            Form {
                if let status {
                    Section { Text(status).font(.footnote).foregroundStyle(.secondary) }
                }

                if !isOwner && (myRole == "viewer" || myRole == "commenter") {
                    Section {
                        RoleRestrictedNotice(
                            role: myRole.capitalized,
                            message: myRole == "viewer"
                                ? "You can view this list. Only editors and the owner can change tasks."
                                : "You can comment on tasks. Only editors and the owner can change them."
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                }

                if isOwner {
                    inviteSection
                }

                Section("Members") {
                    if members.isEmpty {
                        Text("No one yet — share a code to collaborate.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(members) { member in memberRow(member) }
                }

                joinSection

                if isOwner, let share {
                    Section {
                        Button(role: .destructive) { Task { await stopSharing(share) } } label: {
                            Label("Stop Sharing", systemImage: "person.crop.circle.badge.xmark")
                        }
                    } footer: {
                        Text("Removes everyone's access and unshares the list.")
                    }
                }
            }
            .navigationTitle("Share “\(list.name)”")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .overlay { if busy { ProgressView().controlSize(.large) } }
            .task { await load() }
        }
    }

    // MARK: - Sections

    @ViewBuilder private var inviteSection: some View {
        Section("Invite") {
            Picker("Their role", selection: $inviteRole) {
                Text("Editor — can change tasks").tag("editor")
                Text("Commenter — can comment").tag("commenter")
                Text("Viewer — read only").tag("viewer")
            }
            Button { Task { await createInvite() } } label: {
                Label("Create Invite Code", systemImage: "link.badge.plus")
            }
            .disabled(busy)

            if let invite = lastInvite {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Code (\(invite.role))").font(.caption).foregroundStyle(.secondary)
                    Text(invite.token)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(1).truncationMode(.middle)
                    ShareLink(item: shareMessage(invite)) {
                        Label("Share Code", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    @ViewBuilder private var joinSection: some View {
        Section("Join a shared list") {
            TextField("Paste an invite code", text: $joinCode)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button { Task { await join() } } label: {
                Label("Join with Code", systemImage: "person.badge.plus")
            }
            .disabled(busy || joinCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    @ViewBuilder private func memberRow(_ member: ShareMemberDTO) -> some View {
        HStack {
            Image(systemName: member.role == "owner" ? "crown.fill" : "person.fill")
                .foregroundStyle(member.role == "owner" ? .yellow : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(member.userId == myUserId ? "You" : shortId(member.userId))
                    .font(.subheadline)
                Text(member.role.capitalized).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            // The owner can re-role / remove anyone but themselves.
            if isOwner && member.role != "owner" {
                Menu {
                    ForEach(Self.roles, id: \.self) { role in
                        Button { Task { await changeRole(member, to: role) } } label: {
                            if member.role == role { Label(role.capitalized, systemImage: "checkmark") }
                            else { Text(role.capitalized) }
                        }
                    }
                    Divider()
                    Button(role: .destructive) { Task { await remove(member) } } label: {
                        Label("Remove", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Actions

    private func load() async {
        busy = true; defer { busy = false }
        do {
            let s = try await apiClient.shareList(list.id)
            share = s
            members = try await apiClient.shareMembers(shareId: s.id)
        } catch {
            status = "Sharing needs a signed-in connection. Try again when you're online."
        }
    }

    private func createInvite() async {
        guard let share else { return }
        busy = true; defer { busy = false }
        do {
            lastInvite = try await apiClient.createInvite(shareId: share.id, role: inviteRole)
            status = "Invite ready — share the code below."
        } catch { status = "Couldn't create an invite. Check your connection." }
    }

    private func join() async {
        let code = joinCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        busy = true; defer { busy = false }
        do {
            _ = try await apiClient.acceptInvite(token: code)
            await services.syncOnce() // pull the backfilled list + its tasks
            joinCode = ""
            status = "Joined! The shared list is syncing now."
            await load()
        } catch { status = "That code didn't work — it may be expired or already used." }
    }

    private func changeRole(_ member: ShareMemberDTO, to role: String) async {
        guard let share, member.role != role else { return }
        busy = true; defer { busy = false }
        do { try await apiClient.setMemberRole(shareId: share.id, userId: member.userId, role: role); await load() }
        catch { status = "Couldn't update that member's role." }
    }

    private func remove(_ member: ShareMemberDTO) async {
        guard let share else { return }
        busy = true; defer { busy = false }
        do { try await apiClient.removeMember(shareId: share.id, userId: member.userId); await load() }
        catch { status = "Couldn't remove that member." }
    }

    private func stopSharing(_ share: ShareDTO) async {
        busy = true; defer { busy = false }
        do { try await apiClient.stopSharing(shareId: share.id); dismiss() }
        catch { status = "Couldn't stop sharing. Try again." }
    }

    // MARK: - Helpers

    private func shortId(_ id: String) -> String { String(id.prefix(8)) }

    private func shareMessage(_ invite: InviteDTO) -> String {
        "Join my “\(list.name)” list in DoIT as \(invite.role). Invite code:\n\(invite.token)"
    }
}
