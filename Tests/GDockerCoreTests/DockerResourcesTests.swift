import Foundation
import Testing
@testable import GDockerCore

@Suite struct DockerResourcesTests {
    // MARK: - Fixture helpers

    private func fixtureData(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    // MARK: - ImageSummary Tests

    @Test func decodeImagesFixture() throws {
        let data = try fixtureData("images")
        let images = try JSONDecoder().decode([ImageSummary].self, from: data)

        #expect(images.count == 2)

        let first = images[0]
        #expect(first.id == "sha256:e9c7d0e10f9b301936f4051a8b1a8d01d4a04d275727fc378d8542e68447167b")
        #expect(first.repoTags == ["ubuntu:latest", "ubuntu:22.04"])
        #expect(first.size == 77840123)
        #expect(first.created == 1699990000)

        // Dangling image with null RepoTags decodes to empty array
        let second = images[1]
        #expect(second.repoTags == [])
        #expect(second.size == 12345678)
        #expect(second.created == 1699980000)
    }

    // MARK: - VolumeSummary Tests

    @Test func decodeVolumesFixture() throws {
        let data = try fixtureData("volumes")
        struct VolumesResponse: Decodable {
            let volumes: [VolumeSummary]
            enum CodingKeys: String, CodingKey { case volumes = "Volumes" }
        }
        let response = try JSONDecoder().decode(VolumesResponse.self, from: data)
        let volumes = response.volumes

        #expect(volumes.count == 2)

        let first = volumes[0]
        #expect(first.name == "app_data")
        #expect(first.id == "app_data") // computed id { name }
        #expect(first.driver == "local")
        #expect(first.scope == "local")
        #expect(first.createdAt == "2026-01-01T12:00:00Z")

        let second = volumes[1]
        #expect(second.name == "db_data")
        #expect(second.id == "db_data")
        #expect(second.createdAt == "2026-01-02T15:30:00Z")
    }

    // MARK: - NetworkSummary Tests

    @Test func decodeNetworksFixture() throws {
        let data = try fixtureData("networks")
        let networks = try JSONDecoder().decode([NetworkSummary].self, from: data)

        #expect(networks.count == 2)

        let bridge = networks[0]
        #expect(bridge.name == "bridge")
        #expect(bridge.id == "b8f52f8623ad76b5c32bb44a30e8c78c772cb33be85bb6da824db2f8c5b0451a")
        #expect(bridge.driver == "bridge")
        #expect(bridge.scope == "local")
        #expect(bridge.containerCount == 2)

        let isolated = networks[1]
        #expect(isolated.name == "isolated_net")
        #expect(isolated.containerCount == 0)
    }

    // MARK: - PruneReport Tests

    @Test func pruneReportPropertiesAndCodable() throws {
        let report = PruneReport(
            containersDeleted: 3,
            imagesDeleted: 4,
            networksDeleted: 1,
            volumesDeleted: 2,
            spaceReclaimed: 157_286_400
        )
        #expect(report.containersDeleted == 3)
        #expect(report.imagesDeleted == 4)
        #expect(report.networksDeleted == 1)
        #expect(report.volumesDeleted == 2)
        #expect(report.spaceReclaimed == 157_286_400)

        let encoded = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(PruneReport.self, from: encoded)
        #expect(decoded == report)
    }

    // MARK: - Prune Response Decoding Tests

    @Test func decodePruneImagesFixture() throws {
        let data = try fixtureData("prune_images")
        let res = try JSONDecoder().decode(ImagePruneResponse.self, from: data)
        #expect(res.deletedItems == [
            "sha256:1111111111111111111111111111111111111111111111111111111111111111",
            "sha256:2222222222222222222222222222222222222222222222222222222222222222",
        ])
        #expect(res.spaceReclaimed == 52428800)

        // Null images deleted handled gracefully
        let emptyJSON = Data(#"{"ImagesDeleted": null, "SpaceReclaimed": 0}"#.utf8)
        let emptyRes = try JSONDecoder().decode(ImagePruneResponse.self, from: emptyJSON)
        #expect(emptyRes.deletedItems.isEmpty)
        #expect(emptyRes.spaceReclaimed == 0)
    }

    @Test func decodePruneVolumesFixture() throws {
        let data = try fixtureData("prune_volumes")
        let res = try JSONDecoder().decode(VolumePruneResponse.self, from: data)
        #expect(res.volumesDeleted == ["unused_vol_1", "unused_vol_2"])
        #expect(res.spaceReclaimed == 104857600)

        // Null volumes deleted handled gracefully
        let emptyJSON = Data(#"{"VolumesDeleted": null, "SpaceReclaimed": 0}"#.utf8)
        let emptyRes = try JSONDecoder().decode(VolumePruneResponse.self, from: emptyJSON)
        #expect(emptyRes.volumesDeleted == nil)
        #expect(emptyRes.spaceReclaimed == 0)
    }

    @Test func decodePruneNetworksFixture() throws {
        let data = try fixtureData("prune_networks")
        let res = try JSONDecoder().decode(NetworkPruneResponse.self, from: data)
        #expect(res.networksDeleted == ["unused_net_1"])

        // Null networks deleted handled gracefully
        let emptyJSON = Data(#"{"NetworksDeleted": null}"#.utf8)
        let emptyRes = try JSONDecoder().decode(NetworkPruneResponse.self, from: emptyJSON)
        #expect(emptyRes.networksDeleted == nil)
    }

    @Test func decodePruneContainersFixture() throws {
        let data = try fixtureData("prune_containers")
        let res = try JSONDecoder().decode(ContainerPruneResponse.self, from: data)
        #expect(res.containersDeleted == ["stopped_c1", "stopped_c2"])
        #expect(res.spaceReclaimed == 20971520)

        // Null containers deleted handled gracefully
        let emptyJSON = Data(#"{"ContainersDeleted": null, "SpaceReclaimed": 0}"#.utf8)
        let emptyRes = try JSONDecoder().decode(ContainerPruneResponse.self, from: emptyJSON)
        #expect(emptyRes.containersDeleted == nil)
        #expect(emptyRes.spaceReclaimed == 0)
    }

    // MARK: - FakeDocker Integration Tests

    @Test func fakeDockerImageOperations() async throws {
        let fake = FakeDocker()
        let images = try await fake.listImages()
        #expect(images.count == 3)
        #expect(await fake.calls.contains("listImages"))

        try await fake.removeImage("img111", force: true)
        #expect(await fake.calls.contains("removeImage:img111:force=true"))

        let prune = try await fake.pruneImages()
        #expect(prune.deleted == ["img1"])
        #expect(prune.spaceReclaimed == 2048)
        #expect(await fake.calls.contains("pruneImages:all=false"))

        _ = try await fake.pruneImages(all: true)
        #expect(await fake.calls.contains("pruneImages:all=true"))
    }

    @Test func fakeDockerVolumeOperations() async throws {
        let fake = FakeDocker()
        let volumes = try await fake.listVolumes()
        #expect(volumes.count == 2)
        #expect(await fake.calls.contains("listVolumes"))

        try await fake.removeVolume("db_data", force: false)
        #expect(await fake.calls.contains("removeVolume:db_data:force=false"))

        let prune = try await fake.pruneVolumes()
        #expect(prune.deleted == ["vol1"])
        #expect(prune.spaceReclaimed == 4096)
        #expect(await fake.calls.contains("pruneVolumes"))
    }

    @Test func fakeDockerNetworkOperations() async throws {
        let fake = FakeDocker()
        let networks = try await fake.listNetworks()
        #expect(networks.count == 2)
        #expect(await fake.calls.contains("listNetworks"))

        try await fake.removeNetwork("net222")
        #expect(await fake.calls.contains("removeNetwork:net222"))

        let prune = try await fake.pruneNetworks()
        #expect(prune == ["net1"])
        #expect(await fake.calls.contains("pruneNetworks"))
    }

    @Test func fakeDockerPruneContainers() async throws {
        let fake = FakeDocker()
        let prune = try await fake.pruneContainers()
        #expect(prune.deleted == ["c1"])
        #expect(prune.spaceReclaimed == 1024)
        #expect(await fake.calls.contains("pruneContainers"))
    }

    @Test func fakeDockerSystemPruneWithoutVolumes() async throws {
        let fake = FakeDocker()
        let report = try await fake.systemPrune(all: false, volumes: false)

        #expect(report.containersDeleted == 1)
        #expect(report.networksDeleted == 1)
        #expect(report.imagesDeleted == 1)
        #expect(report.volumesDeleted == 0)
        #expect(report.spaceReclaimed == 1024 + 2048) // containers + images only

        let calls = await fake.calls
        #expect(calls.contains("pruneContainers"))
        #expect(calls.contains("pruneNetworks"))
        #expect(calls.contains("pruneImages:all=false"))
        #expect(!calls.contains("pruneVolumes"))

        // Check execution order: containers -> networks -> images
        let containerIndex = try #require(calls.firstIndex(of: "pruneContainers"))
        let networkIndex = try #require(calls.firstIndex(of: "pruneNetworks"))
        let imageIndex = try #require(calls.firstIndex(of: "pruneImages:all=false"))
        #expect(containerIndex < networkIndex)
        #expect(networkIndex < imageIndex)
    }

    @Test func fakeDockerSystemPruneWithVolumes() async throws {
        let fake = FakeDocker()
        let report = try await fake.systemPrune(all: true, volumes: true)

        #expect(report.containersDeleted == 1)
        #expect(report.networksDeleted == 1)
        #expect(report.imagesDeleted == 1)
        #expect(report.volumesDeleted == 1)
        #expect(report.spaceReclaimed == 1024 + 2048 + 4096)

        let calls = await fake.calls
        #expect(calls.contains("pruneContainers"))
        #expect(calls.contains("pruneNetworks"))
        #expect(calls.contains("pruneImages:all=true"))
        #expect(calls.contains("pruneVolumes"))

        // Check execution order: containers -> networks -> images -> volumes
        let containerIndex = try #require(calls.firstIndex(of: "pruneContainers"))
        let networkIndex = try #require(calls.firstIndex(of: "pruneNetworks"))
        let imageIndex = try #require(calls.firstIndex(of: "pruneImages:all=true"))
        let volumeIndex = try #require(calls.firstIndex(of: "pruneVolumes"))
        #expect(containerIndex < networkIndex)
        #expect(networkIndex < imageIndex)
        #expect(imageIndex < volumeIndex)
    }
}
