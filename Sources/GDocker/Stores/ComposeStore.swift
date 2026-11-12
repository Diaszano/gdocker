import Foundation
import GDockerCore
import Observation

@MainActor @Observable
final class ComposeStore {
    private(set) var projects: [ComposeProject] = []
    var selectedProjectName: String?
    var searchText = ""
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

    var activeCount: Int {
        projects.filter { $0.status == .running || $0.status == .partiallyRunning }.count
    }

    var selected: ComposeProject? {
        guard let selectedProjectName else { return nil }
        return projects.first { $0.name == selectedProjectName }
    }

    var filteredProjects: [ComposeProject] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return projects }
        return projects.filter { project in
            project.name.localizedCaseInsensitiveContains(query)
                || project.workingDir.localizedCaseInsensitiveContains(query)
                || project.services.contains { $0.name.localizedCaseInsensitiveContains(query) }
        }
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
