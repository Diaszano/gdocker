import Foundation
import Testing
@testable import GDockerCore

@MainActor
@Suite struct StoresTests {
    @Test func imagesStoreUsageAndFiltering() async {
        let fake = FakeDocker()
        let store = ImagesStore(clientProvider: { fake })
        await store.refresh()

        #expect(store.count == 3)

        let containers = [
            ContainerSummary(
                id: "c1", names: ["/web"], image: "nginx:latest", state: "running",
                status: "Up", labels: [:], ports: []
            ),
            ContainerSummary(
                id: "c2", names: ["/by-short-id"], image: String(FakeDocker.id("img222").prefix(12)), state: "exited",
                status: "Exited", labels: [:], ports: []
            ),
        ]

        let nginx = store.all[0]
        let redis = store.all[1]
        let dangling = store.all[2]

        #expect(store.containerUsageCount(for: nginx, containers: containers) == 1)
        #expect(store.containerUsageCount(for: redis, containers: containers) == 1)
        #expect(store.containerUsageCount(for: dangling, containers: containers) == 0)

        store.filter = .inUse
        #expect(store.filteredImages(containers: containers).map(\.id) == [nginx.id, redis.id])

        store.filter = .dangling
        #expect(store.filteredImages(containers: containers).map(\.id) == [dangling.id])

        store.filter = .all
        store.searchText = "redis"
        #expect(store.filteredImages(containers: containers).map(\.id) == [redis.id])

        await store.remove(id: nginx.id, force: true)
        #expect(await fake.calls.contains("removeImage:\(nginx.id):force=true"))
    }

    @Test func volumesStoreAnonymousDetectionAndFiltering() async {
        let anonName = String(repeating: "a", count: 64)
        #expect(VolumesStore.isAnonymousVolume(anonName))
        #expect(!VolumesStore.isAnonymousVolume("postgres_data"))

        let fake = FakeDocker()
        await fake.setVolumes([
            VolumeSummary(name: "postgres_data", driver: "local", scope: "local"),
            VolumeSummary(name: anonName, driver: "local", scope: "local"),
        ])

        let store = VolumesStore(clientProvider: { fake })
        await store.refresh()

        store.filter = .named
        #expect(store.filteredVolumes.map(\.name) == ["postgres_data"])

        store.filter = .anonymous
        #expect(store.filteredVolumes.map(\.name) == [anonName])

        await store.remove(name: "postgres_data", force: false)
        #expect(await fake.calls.contains("removeVolume:postgres_data:force=false"))
    }

    @Test func networksStoreDefaultProtectionAndFiltering() async {
        #expect(NetworksStore.isDefaultNetworkName("bridge"))
        #expect(NetworksStore.isDefaultNetworkName("HOST"))
        #expect(NetworksStore.isDefaultNetworkName("none"))
        #expect(!NetworksStore.isDefaultNetworkName("app_net"))

        let bridgeID = FakeDocker.id("net111")
        let customID = FakeDocker.id("net222")
        let fake = FakeDocker()
        let store = NetworksStore(clientProvider: { fake })
        store.selectedIDs = [bridgeID, customID]
        await store.refresh()

        // Default network "bridge" is stripped from selection on refresh
        #expect(store.selectedIDs == [customID])

        store.filter = .custom
        #expect(store.filteredNetworks.map(\.name) == ["custom_net"])

        store.filter = .system
        #expect(store.filteredNetworks.map(\.name) == ["bridge"])

        // Attempting to remove both bridge and custom only removes custom
        await store.remove(ids: [bridgeID, customID])
        let calls = await fake.calls
        #expect(!calls.contains("removeNetwork:\(bridgeID)"))
        #expect(calls.contains("removeNetwork:\(customID)"))
    }

    @Test func composeStoreFilteringAndCleanDownProjects() async {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cs-\(UUID().uuidString)")
        let registry = ComposeProjectRegistry(fileURL: dir.appendingPathComponent("projects.json"))
        let runner = FakeComposeRunner()

        let activeContainer = ContainerSummary(
            id: "c1", names: ["/app-web-1"], image: "nginx", state: "running", status: "Up",
            labels: [
                "com.docker.compose.project": "active-stack",
                "com.docker.compose.project.working_dir": "/tmp/active",
                "com.docker.compose.service": "web",
            ],
            ports: []
        )
        let downContainer = ContainerSummary(
            id: "c2", names: ["/old-db-1"], image: "postgres", state: "exited", status: "Exited",
            labels: [
                "com.docker.compose.project": "old-stack",
                "com.docker.compose.project.working_dir": "/tmp/old",
                "com.docker.compose.service": "db",
            ],
            ports: []
        )

        await registry.ingest([activeContainer, downContainer])

        let store = ComposeStore(
            containersProvider: { [activeContainer] },
            registry: registry,
            runner: runner
        )
        await store.refresh()

        #expect(store.count == 2)
        #expect(store.activeCount == 1)
        #expect(store.downCount == 1)

        store.filter = .running
        #expect(store.filteredProjects.map(\.name) == ["active-stack"])

        store.filter = .stopped
        #expect(store.filteredProjects.map(\.name) == ["old-stack"])

        await store.cleanDownProjects()
        #expect(store.projects.map(\.name) == ["active-stack"])
    }
}
