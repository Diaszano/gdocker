import Foundation

/// What the MCP tool router and app stores need from Docker. A protocol so tests can use a fake.
public protocol DockerOperations: Sendable {
    func listContainers() async throws -> [ContainerSummary]
    func inspect(_ id: String) async throws -> (details: ContainerDetails, rawJSON: String)
    func recentLogs(_ id: String, tail: Int, timestamps: Bool) async throws -> [LogLine]
    func statsOnce(_ id: String) async throws -> StatsSample
    func start(_ id: String) async throws
    func stop(_ id: String) async throws
    func restart(_ id: String) async throws
    func remove(_ id: String, force: Bool) async throws
    func exec(_ id: String, command: [String]) async throws -> ExecResult

    // Images
    func listImages() async throws -> [ImageSummary]
    func removeImage(_ id: String, force: Bool) async throws
    func pruneImages(all: Bool) async throws -> (deleted: [String], spaceReclaimed: Int64)

    // Volumes
    func listVolumes() async throws -> [VolumeSummary]
    func removeVolume(_ name: String, force: Bool) async throws
    func pruneVolumes() async throws -> (deleted: [String], spaceReclaimed: Int64)

    // Networks
    func listNetworks() async throws -> [NetworkSummary]
    func removeNetwork(_ id: String) async throws
    func pruneNetworks() async throws -> [String]

    // Containers prune & system prune
    func pruneContainers() async throws -> (deleted: [String], spaceReclaimed: Int64)
    func systemPrune(all: Bool, volumes: Bool) async throws -> PruneReport
}

extension DockerOperations {
    public func listImages() async throws -> [ImageSummary] { [] }
    public func removeImage(_ id: String, force: Bool = false) async throws {}
    public func pruneImages(all: Bool = false) async throws -> (deleted: [String], spaceReclaimed: Int64) {
        (deleted: [], spaceReclaimed: 0)
    }

    public func listVolumes() async throws -> [VolumeSummary] { [] }
    public func removeVolume(_ name: String, force: Bool = false) async throws {}
    public func pruneVolumes() async throws -> (deleted: [String], spaceReclaimed: Int64) {
        (deleted: [], spaceReclaimed: 0)
    }

    public func listNetworks() async throws -> [NetworkSummary] { [] }
    public func removeNetwork(_ id: String) async throws {}
    public func pruneNetworks() async throws -> [String] { [] }

    public func pruneContainers() async throws -> (deleted: [String], spaceReclaimed: Int64) {
        (deleted: [], spaceReclaimed: 0)
    }

    public func systemPrune(all: Bool = false, volumes: Bool = false) async throws -> PruneReport {
        let containers = try await pruneContainers()
        let networks = try await pruneNetworks()
        let images = try await pruneImages(all: all)
        let volumesReport = volumes ? try await pruneVolumes() : (deleted: [], spaceReclaimed: 0)
        return PruneReport(
            containersDeleted: containers.deleted.count,
            imagesDeleted: images.deleted.count,
            networksDeleted: networks.count,
            volumesDeleted: volumesReport.deleted.count,
            spaceReclaimed: containers.spaceReclaimed + images.spaceReclaimed + volumesReport.spaceReclaimed
        )
    }
}

extension DockerClient: DockerOperations {}
