import GDockerCore
import Observation

/// What the AI did through MCP, newest first, refreshed whenever the log changes.
@MainActor @Observable
final class ActivityModel {
    private(set) var entries: [ActivityEntry] = []
    private var watcher: Task<Void, Never>?

    init(log: ActivityLog) {
        watcher = Task { [weak self] in
            let changes = await log.changes()
            let current = await log.entries()
            self?.entries = current
            for await _ in changes {
                let latest = await log.entries()
                self?.entries = latest
            }
        }
    }
}
