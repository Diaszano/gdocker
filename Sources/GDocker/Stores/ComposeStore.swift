import Foundation
import GDockerCore
import Observation

enum ComposeFilter: String, CaseIterable, Sendable {
    case all, running, partial, stopped
}

@MainActor @Observable
final class ComposeStore {
    private(set) var projects: [ComposeProject] = []
    var selectedProjectName: String?
    var searchText = ""
    var filter: ComposeFilter = .all
    var lastError: String?
    var isPerformingAction = false
    private(set) var isComposeAvailable = true

    private let store: ContainersStore
    private let registry: ComposeProjectRegistry
    private let runner: any ComposeOperations

    init(
        store: ContainersStore,
        registry: ComposeProjectRegistry,
        runner: any ComposeOperations = CLIComposeRunner()
    ) {
        self.store = store
        self.registry = registry
        self.runner = runner
    }

    convenience init(store: ContainersStore, runner: any ComposeOperations = CLIComposeRunner()) {
        self.init(store: store, registry: ComposeProjectRegistry(), runner: runner)
    }

    var count: Int { projects.count }

    var activeCount: Int { projects.filter(\.isActive).count }

    var selected: ComposeProject? {
        guard let selectedProjectName else { return nil }
        return projects.first { $0.name == selectedProjectName }
    }

    var filteredProjects: [ComposeProject] {
        projects.filter { project in
            switch filter {
            case .all: break
            case .running:
                if project.status != .running { return false }
            case .partial:
                if project.status != .partiallyRunning { return false }
            case .stopped:
                if project.status != .stopped && project.status != .down { return false }
            }
            return project.matches(searchText)
        }
    }

    var downCount: Int {
        projects.filter { $0.status == .down }.count
    }

    func cleanDownProjects() async {
        for project in projects where project.status == .down {
            await registry.removeProject(named: project.name)
        }
        await refresh()
    }

    func refresh() async {
        isComposeAvailable = await runner.isComposeAvailable()
        let containers = store.all
        projects = await registry.projects(containers: containers)
        if let selectedProjectName, !projects.contains(where: { $0.name == selectedProjectName }) {
            self.selectedProjectName = nil
        }
    }

    func up(project: ComposeProject) async {
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            _ = try await runner.composeUp(
                project: project.name,
                workingDir: project.workingDir,
                configFiles: project.configFiles
            )
            lastError = nil
            await store.refresh()
            await refresh()
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    func down(project: ComposeProject, removeVolumes: Bool = false) async {
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            _ = try await runner.composeDown(
                project: project.name,
                workingDir: project.workingDir,
                configFiles: project.configFiles,
                removeVolumes: removeVolumes
            )
            lastError = nil
            await store.refresh()
            await refresh()
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    func forget(project: ComposeProject) async {
        await registry.removeProject(named: project.name)
        await refresh()
    }
}
