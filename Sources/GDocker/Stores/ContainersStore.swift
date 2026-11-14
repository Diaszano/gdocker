import GDockerCore
import Observation

enum ContainerAction { case start, stop, restart, remove }

@MainActor @Observable
final class ContainersStore {
    private(set) var connected = false
    private(set) var client: DockerClient?
    private(set) var hostInfo: DockerHostInfo?
    var selectedID: String?
    var lastError: String?
    /// Bumped after every action. A restart can finish between two polls, leaving id and state unchanged, while Docker
    /// has already closed the container's log stream; views key their streams on this to reopen them.
    private(set) var revision = 0
    var searchText = ""
    var statusFilter: ContainerStatusFilter = .all
    var selectedIDs: Set<String> = []

    private(set) var all: [ContainerSummary] = []
    private var loop: Task<Void, Never>?
    private var usageTask: Task<Void, Never>?

    var selected: ContainerSummary? { all.first { $0.id == selectedID } }

    var visibleGroups: [ContainerGroup] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let matching = all.filter { container in
            guard statusFilter.matches(container) else { return false }
            if query.isEmpty { return true }
            return container.name.localizedCaseInsensitiveContains(query)
                || container.image.localizedCaseInsensitiveContains(query)
        }
        return groupByCompose(matching)
    }

    // shortcut: polling every 2s instead of the /events stream; switch to /events if the CPU cost shows up
    func start() {
        guard loop == nil else { return }
        loop = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func perform(_ action: ContainerAction, on id: String) async {
        await performBulk(action, on: [id])
    }

    func performBulk(_ action: ContainerAction, on ids: Set<String>) async {
        guard let client, !ids.isEmpty else { return }
        var errors: [String] = []
        for id in ids {
            do {
                switch action {
                case .start: try await client.start(id)
                case .stop: try await client.stop(id)
                case .restart: try await client.restart(id)
                case .remove:
                    let running = all.first { $0.id == id }?.statusKind == .running
                    try await client.remove(id, force: running)
                }
            } catch {
                errors.append(error.localizedDescription)
            }
        }
        if action == .remove {
            selectedIDs.subtract(ids)
        }
        lastError = errors.isEmpty ? nil : errors.joined(separator: "\n")
        revision += 1
        await refresh()
    }

    @discardableResult
    func pruneStopped() async -> (deletedCount: Int, spaceReclaimed: Int64)? {
        guard let client else { return nil }
        do {
            let report = try await client.pruneContainers()
            lastError = nil
            revision += 1
            await refresh()
            return (report.deleted.count, report.spaceReclaimed)
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func refresh() async {
        do {
            if client == nil { client = try DockerClient.connect() }
            guard let client else { return }
            all = try await client.listContainers()
            if hostInfo == nil {
                hostInfo = try? await client.hostInfo()
            }
            if usageTask == nil {
                let runningIDs = all.filter { $0.statusKind == .running }.map(\.id)
                usageTask = Task { [weak self] in
                    defer { self?.usageTask = nil }
                    let usage = await client.hostUsage(runningIDs: runningIDs)
                    if let current = self?.hostInfo {
                        self?.hostInfo = current.withUsage(cpuPercent: usage.cpuPercent, memUsed: usage.memUsed)
                    }
                }
            }
            connected = true
            selectedIDs.formIntersection(Set(all.map(\.id)))
            if let selectedID, !all.contains(where: { $0.id == selectedID }) { self.selectedID = nil }
        } catch {
            connected = false
            all = []
            selectedID = nil
            // AsyncHTTPClient crashes if a client is dropped without shutdown. Clear the property first so a
            // concurrent refresh doesn't shut the same client down twice.
            if let stale = client {
                client = nil
                await stale.shutdown()
            }
        }
    }
}
