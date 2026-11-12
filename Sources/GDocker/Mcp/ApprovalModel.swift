import GDockerCore
import Observation

/// The approval requests waiting for the user, oldest first, kept in sync with the queue the router asks.
@MainActor @Observable
final class ApprovalModel {
    private(set) var pending: [ApprovalRequest] = []
    private let queue: ApprovalQueue
    private var watcher: Task<Void, Never>?

    init(queue: ApprovalQueue) {
        self.queue = queue
        watcher = Task { [weak self] in
            let changes = await queue.changes()
            let current = await queue.pending()
            self?.pending = current
            for await list in changes { self?.pending = list }
        }
    }

    /// The request shown to the user: the one that has waited longest.
    var current: ApprovalRequest? { pending.first }

    /// Answering twice is harmless: the queue ignores a request that is already resolved.
    func answer(_ decision: ApprovalDecision) {
        guard let id = current?.id else { return }
        let queue = queue
        Task { await queue.resolve(id, decision) }
    }
}
