import SwiftUI
import SyncCore
import DesignSystem

/// Comments + @mentions on a task (DevelopmentPlan P5-5, AppSpec §16.4). The thread lives on the
/// server (shared with the list's members); this fetches it live and posts new comments through
/// `POST /tasks/:id/comments`, where the server extracts `@mentions` and fans the comment out to every
/// member via the change log.
///
/// **Account/network-bound:** with no reachable server the thread is empty and posting no-ops, so the
/// section degrades to inert rather than blocking the editor. It's only shown in server-connected
/// builds (`AppConfig.isLiveSync`).
struct TaskCommentsSection: View {
    @Environment(AppServices.self) private var services
    let taskId: String

    @State private var comments: [CommentDTO] = []
    @State private var draft = ""
    @State private var sending = false
    @State private var loadState: LoadState = .loading

    private enum LoadState { case loading, loaded, failed }

    private var apiClient: APIClient { services.apiClient }
    private var myUserId: String { services.currentOwnerId }

    var body: some View {
        Section("Comments") {
            if loadState == .loading && comments.isEmpty {
                LoadingSkeleton(rows: 3)
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            } else if loadState == .failed && comments.isEmpty {
                RecoverableErrorView(title: "Couldn't load comments",
                                     message: "Check your connection and try again.",
                                     retryTitle: "Retry") { Task { await load() } }
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            } else {
            if comments.isEmpty {
                Text("No comments yet.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(comments) { comment in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(comment.ownerId == myUserId ? "You" : String(comment.ownerId.prefix(8)))
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if let created = comment.createdAt {
                            Text(String(created.prefix(16))).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    Text(comment.body)
                    if let mentions = comment.mentions, !mentions.isEmpty {
                        Text(mentions.map { "@\($0)" }.joined(separator: " "))
                            .font(.caption2).foregroundStyle(.tint)
                    }
                }
                .padding(.vertical, 2)
            }
            HStack(alignment: .bottom) {
                TextField("Add a comment… use @name to mention", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                Button { Task { await send() } } label: { Image(systemName: "paperplane.fill") }
                    .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Post comment")
            }
            }
        }
        .task { await load() }
    }

    private func load() async {
        if comments.isEmpty { loadState = .loading }
        do {
            comments = try await apiClient.taskComments(taskId: taskId)
            loadState = .loaded
        } catch {
            loadState = .failed
        }
    }

    private func send() async {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        sending = true; defer { sending = false }
        if (try? await apiClient.postComment(taskId: taskId, body: body)) != nil {
            draft = ""
            await load()
        }
    }
}
