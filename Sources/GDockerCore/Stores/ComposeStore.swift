import Foundation
import Observation

public enum ComposeFilter: String, CaseIterable, Sendable {
    case all, running, partial, stopped
}

@MainActor @Observable
public final class ComposeStore {
    public private(set) var projects: [ComposeProject] = []
    public var selectedProjectName: String?
    public var searchText = ""
    public var filter: ComposeFilter = .all
    public var lastError: String?
    public var isPerformingAction = false
    public private(set) var isComposeAvailable = true

    private let containersProvider: @MainActor () -> [ContainerSummary]
    private let refreshContainers: @MainActor () async -> Void
    private let registry: ComposeProjectRegistry
    private let runner: any ComposeOperations

    public init(
        containersProvider: @MainActor @escaping () -> [ContainerSummary] = { [] },
        refreshContainers: @MainActor @escaping () async -> Void = {},
        registry: ComposeProjectRegistry,
        runner: any ComposeOperations = CLIComposeRunner()
    ) {
        self.containersProvider = containersProvider
        self.refreshContainers = refreshContainers
        self.registry = registry
        self.runner = runner
    }

    public var count: Int { projects.count }

    public var activeCount: Int { projects.filter(\.isActive).count }

    public var selected: ComposeProject? {
        guard let selectedProjectName else { return nil }
        return projects.first { $0.name == selectedProjectName }
    }

    public var filteredProjects: [ComposeProject] {
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

    public var downCount: Int {
        projects.filter { $0.status == .down }.count
    }

    public func cleanDownProjects() async {
        for project in projects where project.status == .down {
            await registry.removeProject(named: project.name)
        }
        await refresh()
    }

    public func refresh() async {
        isComposeAvailable = await runner.isComposeAvailable()
        let containers = containersProvider()
        projects = await registry.projects(containers: containers)
        if let selectedProjectName, !projects.contains(where: { $0.name == selectedProjectName }) {
            self.selectedProjectName = nil
        }
    }

    public func up(project: ComposeProject) async {
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            _ = try await runner.composeUp(
                project: project.name,
                workingDir: project.workingDir,
                configFiles: project.configFiles
            )
            lastError = nil
            await refreshContainers()
            await refresh()
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    public func down(project: ComposeProject, removeVolumes: Bool = false) async {
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
            await refreshContainers()
            await refresh()
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    public func forget(project: ComposeProject) async {
        await registry.removeProject(named: project.name)
        await refresh()
    }
}
