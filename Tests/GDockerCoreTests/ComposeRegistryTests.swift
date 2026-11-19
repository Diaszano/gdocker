import Foundation
import Testing

@testable import GDockerCore

@Suite("ComposeRegistryTests")
struct ComposeRegistryTests {

    private func makeContainer(
        id: String,
        project: String,
        service: String,
        state: String = "running",
        status: String = "Up 2 hours",
        workingDir: String = "/path/to/project",
        configFiles: String = "docker-compose.yml"
    ) -> ContainerSummary {
        let labels: [String: String] = [
            "com.docker.compose.project": project,
            "com.docker.compose.service": service,
            "com.docker.compose.project.working_dir": workingDir,
            "com.docker.compose.project.config_files": configFiles,
        ]
        return ContainerSummary(
            id: id,
            names: ["/\(project)-\(service)-1"],
            image: "\(service):latest",
            state: state,
            status: status,
            labels: labels,
            ports: []
        )
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("compose-test-\(UUID().uuidString).json")
    }

    @Test func ingestExtractsMetadataAndAccumulatesServices() async throws {
        let tempURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let registry = ComposeProjectRegistry(fileURL: tempURL)

        let c1 = makeContainer(id: "c1", project: "my-app", service: "web")
        let c2 = makeContainer(id: "c2", project: "my-app", service: "db")
        let nonCompose = ContainerSummary(
            id: "c3",
            names: ["/standalone"],
            image: "redis:latest",
            state: "running",
            status: "Up 1 hour",
            labels: [:],
            ports: []
        )

        await registry.ingest([c1, c2, nonCompose])

        let records = await registry.records()
        #expect(records.count == 1)
        let record = try #require(records.first)
        #expect(record.name == "my-app")
        #expect(record.workingDir == "/path/to/project")
        #expect(record.configFiles == ["docker-compose.yml"])
        #expect(record.serviceNames.sorted() == ["db", "web"])
    }

    @Test func configFilesSplitsAndTrimsWhitespace() async throws {
        let tempURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let registry = ComposeProjectRegistry(fileURL: tempURL)
        let c = makeContainer(
            id: "c1",
            project: "multi-config",
            service: "api",
            configFiles: "docker-compose.yml, docker-compose.override.yml , compose.local.yml"
        )

        await registry.ingest([c])

        let records = await registry.records()
        let record = try #require(records.first)
        #expect(
            record.configFiles == [
                "docker-compose.yml",
                "docker-compose.override.yml",
                "compose.local.yml",
            ])
    }

    @Test func statusComputationAllRunning() async throws {
        let tempURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let registry = ComposeProjectRegistry(fileURL: tempURL)
        let c1 = makeContainer(id: "c1", project: "stack", service: "web", state: "running", status: "Up 3 hours")
        let c2 = makeContainer(id: "c2", project: "stack", service: "db", state: "running", status: "Up 3 hours")

        let projects = await registry.projects(containers: [c1, c2])
        #expect(projects.count == 1)
        let project = try #require(projects.first)
        #expect(project.name == "stack")
        #expect(project.status == .running)
        #expect(project.services.count == 2)
        #expect(project.services.allSatisfy { $0.statusKind == .running && $0.containerID != nil })
    }

    @Test func statusComputationPartiallyRunningWhenMixed() async throws {
        let tempURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let registry = ComposeProjectRegistry(fileURL: tempURL)
        let c1 = makeContainer(id: "c1", project: "stack", service: "web", state: "running", status: "Up 3 hours")
        let c2 = makeContainer(
            id: "c2", project: "stack", service: "db", state: "exited", status: "Exited (0) 5 mins ago")

        let projects = await registry.projects(containers: [c1, c2])
        let project = try #require(projects.first)
        #expect(project.status == .partiallyRunning)
    }

    @Test func statusComputationPartiallyRunningWhenServiceMissingContainer() async throws {
        let tempURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let registry = ComposeProjectRegistry(fileURL: tempURL)
        // First see both services
        let c1 = makeContainer(id: "c1", project: "stack", service: "web", state: "running", status: "Up 3 hours")
        let c2 = makeContainer(id: "c2", project: "stack", service: "db", state: "running", status: "Up 3 hours")
        await registry.ingest([c1, c2])

        // Now only web is running, db container was removed
        let projects = await registry.projects(containers: [c1])
        let project = try #require(projects.first)
        #expect(project.status == .partiallyRunning)
        #expect(project.services.count == 2)
        let dbService = try #require(project.services.first { $0.name == "db" })
        #expect(dbService.containerID == nil)
        #expect(dbService.state == nil)
        #expect(dbService.statusKind == nil)
    }

    @Test func statusComputationAllStopped() async throws {
        let tempURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let registry = ComposeProjectRegistry(fileURL: tempURL)
        let c1 = makeContainer(
            id: "c1", project: "stack", service: "web", state: "exited", status: "Exited (0) 1 hour ago")
        let c2 = makeContainer(
            id: "c2", project: "stack", service: "db", state: "exited", status: "Exited (1) 1 hour ago")

        let projects = await registry.projects(containers: [c1, c2])
        let project = try #require(projects.first)
        #expect(project.status == .stopped)
    }

    @Test func statusComputationDownPreservesServices() async throws {
        let tempURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let registry = ComposeProjectRegistry(fileURL: tempURL)
        let c1 = makeContainer(id: "c1", project: "stack", service: "web")
        let c2 = makeContainer(id: "c2", project: "stack", service: "db")
        await registry.ingest([c1, c2])

        // All containers are gone (down)
        let projects = await registry.projects(containers: [])
        #expect(projects.count == 1)
        let project = try #require(projects.first)
        #expect(project.status == .down)
        #expect(project.services.count == 2)
        #expect(project.services.map(\.name).sorted() == ["db", "web"])
        #expect(project.services.allSatisfy { $0.containerID == nil && $0.state == nil && $0.statusKind == nil })
    }

    @Test func persistenceRoundTripAcrossRegistryInstances() async throws {
        let tempURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let registryA = ComposeProjectRegistry(fileURL: tempURL)
        let c1 = makeContainer(id: "c1", project: "app-a", service: "web", workingDir: "/app/a")
        let c2 = makeContainer(id: "c2", project: "app-b", service: "api", workingDir: "/app/b")
        await registryA.ingest([c1, c2])

        // Verify file was written
        #expect(FileManager.default.fileExists(atPath: tempURL.path))

        // Create new instance pointing to same file
        let registryB = ComposeProjectRegistry(fileURL: tempURL)
        let recordsB = await registryB.records()
        #expect(recordsB.count == 2)
        #expect(recordsB.map(\.name).sorted() == ["app-a", "app-b"])

        let appA = try #require(recordsB.first { $0.name == "app-a" })
        #expect(appA.workingDir == "/app/a")
        #expect(appA.serviceNames == ["web"])
    }

    @Test func removeProjectRemovesFromMemoryAndDisk() async throws {
        let tempURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let registryA = ComposeProjectRegistry(fileURL: tempURL)
        let c1 = makeContainer(id: "c1", project: "proj-1", service: "svc")
        let c2 = makeContainer(id: "c2", project: "proj-2", service: "svc")
        await registryA.ingest([c1, c2])

        await registryA.removeProject(named: "proj-1")
        let recordsA = await registryA.records()
        #expect(recordsA.count == 1)
        #expect(recordsA.first?.name == "proj-2")

        // Reload in new instance
        let registryB = ComposeProjectRegistry(fileURL: tempURL)
        let recordsB = await registryB.records()
        #expect(recordsB.count == 1)
        #expect(recordsB.first?.name == "proj-2")
    }

    @Test func projectsSortedAlphabetically() async {
        let tempURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let registry = ComposeProjectRegistry(fileURL: tempURL)
        let c1 = makeContainer(id: "c1", project: "zeta", service: "worker")
        let c2 = makeContainer(id: "c2", project: "alpha", service: "web")
        let c3 = makeContainer(id: "c3", project: "mid", service: "db")

        let projects = await registry.projects(containers: [c1, c2, c3])
        #expect(projects.map(\.name) == ["alpha", "mid", "zeta"])
    }

    @Test func modelsCodableRoundTrip() throws {
        let service = ComposeServiceSummary(
            name: "web",
            containerID: "cid123",
            state: "running",
            statusKind: .running
        )
        let project = ComposeProject(
            name: "demo",
            workingDir: "/demo",
            configFiles: ["docker-compose.yml"],
            services: [service],
            status: .running
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(project)
        let decoded = try JSONDecoder().decode(ComposeProject.self, from: data)

        #expect(decoded == project)
        #expect(decoded.id == "demo")
        #expect(decoded.services.first?.id == "cid123")
    }

    @Test func scaledServiceHasDistinctIdentifiableIDs() async throws {
        let tempURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let registry = ComposeProjectRegistry(fileURL: tempURL)
        let c1 = makeContainer(id: "c1", project: "stack", service: "worker")
        let c2 = makeContainer(id: "c2", project: "stack", service: "worker")
        let projects = await registry.projects(containers: [c1, c2])
        let project = try #require(projects.first)
        #expect(project.services.count == 2)
        #expect(Set(project.services.map(\.id)) == ["c1", "c2"])
    }
}
