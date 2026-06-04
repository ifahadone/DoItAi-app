import Foundation
import SyncCore

/// The realtime client (AppSpec §5.8, DevelopmentPlan P5-4). Holds a WebSocket to `/ws`; on a
/// `sync.bump` it triggers a pull — the durable, conflict-resolved truth always flows through
/// `sync/pull`, so a dropped socket is harmless (the next pull is complete, and we reconnect).
///
/// **Network/device-bound:** delivery needs a reachable socket; without one, the app falls back to
/// pull-on-foreground/interval (exactly the spec's polling fallback).
@MainActor
final class RealtimeClient {
    private let apiClient: APIClient
    private let onBump: () async -> Void
    private var task: URLSessionWebSocketTask?
    private var active = false

    init(apiClient: APIClient, onBump: @escaping () async -> Void) {
        self.apiClient = apiClient
        self.onBump = onBump
    }

    /// Mint a ticket, open the socket, and start receiving. Idempotent.
    func connect() async {
        guard !active else { return }
        guard let ticket = try? await apiClient.wsTicket(), let url = await apiClient.webSocketURL(ticket: ticket) else { return }
        let socket = URLSession.shared.webSocketTask(with: url)
        task = socket
        active = true
        socket.resume()
        receiveNext()
    }

    func disconnect() {
        active = false
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }

    private func receiveNext() {
        task?.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.active else { return }
                switch result {
                case .success(let message):
                    if case let .string(text) = message, case .bump = RealtimeEvent.parse(text) {
                        await self.onBump()
                    }
                    self.receiveNext() // keep listening
                case .failure:
                    // Socket dropped — the next foreground pull keeps the app consistent.
                    self.active = false
                }
            }
        }
    }
}
