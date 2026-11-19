import Foundation

@testable import GDockerCore

/// In-memory Docker for router tests. Records every call so a test can prove Docker was (not) touched.
actor FakeDocker: DockerOperations {
    static func id(_ prefix: String) -> String { prefix + String(repeating: "0", count: 64 - prefix.count) }

    private(set) var calls: [String] = []
    private(set) var requestedTail: Int?
    var failure: Error?
    var execResult = ExecResult(exitCode: 0, stdout: "hi\n", stderr: "", truncated: false)

    let containers: [ContainerSummary] = [
        FakeDocker.make("web", id: FakeDocker.id("aaa111"), state: "running", status: "Up 2 hours"),
        FakeDocker.make("web-2", id: FakeDocker.id("ccc333"), state: "exited", status: "Exited (0) 1 day ago"),
        FakeDocker.make("db", id: FakeDocker.id("bbb222"), state: "running", status: "Up 2 hours", project: "app"),
        FakeDocker.make("svc-a", id: FakeDocker.id("abc111"), state: "running", status: "Up 1 hour"),
        FakeDocker.make("svc-b", id: FakeDocker.id("abc222"), state: "running", status: "Up 1 hour"),
    ]

    var images: [ImageSummary] = [
        ImageSummary(
            id: FakeDocker.id("img111"), repoTags: ["nginx:latest"], size: 142_000_000, created: 1_700_000_000),
        ImageSummary(id: FakeDocker.id("img222"), repoTags: ["redis:alpine"], size: 35_000_000, created: 1_700_001_000),
        ImageSummary(id: FakeDocker.id("img333"), repoTags: [], size: 50_000_000, created: 1_700_002_000),
    ]

    var volumes: [VolumeSummary] = [
        VolumeSummary(name: "db_data", driver: "local", scope: "local", createdAt: "2026-01-01T00:00:00Z"),
        VolumeSummary(name: "cache", driver: "local", scope: "local", createdAt: "2026-01-02T00:00:00Z"),
    ]

    var networks: [NetworkSummary] = [
        NetworkSummary(
            id: FakeDocker.id("net111"), name: "bridge", driver: "bridge", scope: "local", containerCount: 2),
        NetworkSummary(
            id: FakeDocker.id("net222"), name: "custom_net", driver: "bridge", scope: "local", containerCount: 0),
    ]

    var pruneContainersResult: (deleted: [String], spaceReclaimed: Int64) = (["c1"], 1024)
    var pruneImagesResult: (deleted: [String], spaceReclaimed: Int64) = (["img1"], 2048)
    var pruneVolumesResult: (deleted: [String], spaceReclaimed: Int64) = (["vol1"], 4096)
    var pruneNetworksResult: [String] = ["net1"]

    private static func make(
        _ name: String, id: String, state: String, status: String, project: String? = nil
    ) -> ContainerSummary {
        ContainerSummary(
            id: id, names: ["/\(name)"], image: "img:\(name)", state: state, status: status,
            labels: project.map { ["com.docker.compose.project": $0] } ?? [:],
            ports: [PortBinding(ip: "0.0.0.0", privatePort: 80, publicPort: 8080, type: "tcp")])
    }

    func setFailure(_ error: Error?) { failure = error }
    func setExecResult(_ result: ExecResult) { execResult = result }

    private func record(_ call: String) throws {
        calls.append(call)
        if let failure { throw failure }
    }

    func listContainers() async throws -> [ContainerSummary] {
        try record("listContainers")
        return containers
    }

    func inspect(_ id: String) async throws -> (details: ContainerDetails, rawJSON: String) {
        try record("inspect:\(id)")
        let raw = """
            {"Id":"\(id)","Name":"/web","Config":{"Image":"nginx","Env":["SECRET=hunter2","PLAIN=1"],"Tty":false},\
            "State":{"Status":"running","StartedAt":"2026-01-01T00:00:00Z"}}
            """
        return (try JSONDecoder().decode(ContainerDetails.self, from: Data(raw.utf8)), raw)
    }

    func recentLogs(_ id: String, tail: Int, timestamps: Bool) async throws -> [LogLine] {
        try record("logs:\(id)")
        requestedTail = tail
        return [
            LogLine(id: 1, stream: .stdout, timestamp: nil, text: "first"),
            LogLine(id: 2, stream: .stderr, timestamp: nil, text: "second"),
        ]
    }

    func statsOnce(_ id: String) async throws -> StatsSample {
        try record("stats:\(id)")
        let json = Data(
            """
            {"cpu_stats":{"cpu_usage":{"total_usage":400},"system_cpu_usage":2000,"online_cpus":4},
             "precpu_stats":{"cpu_usage":{"total_usage":200},"system_cpu_usage":1000},
             "memory_stats":{"usage":600,"limit":1000}}
            """.utf8)
        guard let sample = try StatsSample.from(json: json) else { throw FakeDockerError.missing }
        return sample
    }

    func start(_ id: String) async throws { try record("start:\(id)") }
    func stop(_ id: String) async throws { try record("stop:\(id)") }
    func restart(_ id: String) async throws { try record("restart:\(id)") }
    func remove(_ id: String, force: Bool) async throws { try record("remove:\(id):force=\(force)") }

    func exec(_ id: String, command: [String]) async throws -> ExecResult {
        try record("exec:\(id):\(command.joined(separator: " "))")
        return execResult
    }

    // MARK: - Images

    func listImages() async throws -> [ImageSummary] {
        try record("listImages")
        return images
    }

    func removeImage(_ id: String, force: Bool) async throws {
        try record("removeImage:\(id):force=\(force)")
    }

    func pruneImages(all: Bool = false) async throws -> (deleted: [String], spaceReclaimed: Int64) {
        try record("pruneImages:all=\(all)")
        return pruneImagesResult
    }

    // MARK: - Volumes

    func listVolumes() async throws -> [VolumeSummary] {
        try record("listVolumes")
        return volumes
    }

    func removeVolume(_ name: String, force: Bool) async throws {
        try record("removeVolume:\(name):force=\(force)")
    }

    func pruneVolumes() async throws -> (deleted: [String], spaceReclaimed: Int64) {
        try record("pruneVolumes")
        return pruneVolumesResult
    }

    // MARK: - Networks

    func listNetworks() async throws -> [NetworkSummary] {
        try record("listNetworks")
        return networks
    }

    func removeNetwork(_ id: String) async throws {
        try record("removeNetwork:\(id)")
    }

    func pruneNetworks() async throws -> [String] {
        try record("pruneNetworks")
        return pruneNetworksResult
    }

    // MARK: - Containers Prune & System Prune

    func pruneContainers() async throws -> (deleted: [String], spaceReclaimed: Int64) {
        try record("pruneContainers")
        return pruneContainersResult
    }

    func systemPrune(all: Bool = false, volumes: Bool = false) async throws -> PruneReport {
        try record("systemPrune:all=\(all):volumes=\(volumes)")
        let c = try await pruneContainers()
        let n = try await pruneNetworks()
        let i = try await pruneImages(all: all)
        let v = volumes ? try await pruneVolumes() : (deleted: [], spaceReclaimed: 0)
        return PruneReport(
            containersDeleted: c.deleted.count,
            imagesDeleted: i.deleted.count,
            networksDeleted: n.count,
            volumesDeleted: v.deleted.count,
            spaceReclaimed: c.spaceReclaimed + i.spaceReclaimed + v.spaceReclaimed
        )
    }

    func setImages(_ images: [ImageSummary]) { self.images = images }
    func setVolumes(_ volumes: [VolumeSummary]) { self.volumes = volumes }
    func setNetworks(_ networks: [NetworkSummary]) { self.networks = networks }
    func setPruneContainersResult(_ result: (deleted: [String], spaceReclaimed: Int64)) {
        pruneContainersResult = result
    }
    func setPruneImagesResult(_ result: (deleted: [String], spaceReclaimed: Int64)) { pruneImagesResult = result }
    func setPruneVolumesResult(_ result: (deleted: [String], spaceReclaimed: Int64)) { pruneVolumesResult = result }
    func setPruneNetworksResult(_ result: [String]) { pruneNetworksResult = result }
}

enum FakeDockerError: Error { case missing }

/// Answers approval requests from a script and records them. Out of script answers deny.
actor ScriptedPrompter: ApprovalPrompter {
    private var decisions: [ApprovalDecision]
    private(set) var requests: [ApprovalRequest] = []

    init(_ decisions: [ApprovalDecision] = []) { self.decisions = decisions }

    func decide(_ request: ApprovalRequest) async -> ApprovalDecision {
        requests.append(request)
        return decisions.isEmpty ? .deny : decisions.removeFirst()
    }
}

/// Never answers; returns `.deny` only when cancelled, like a user who walked away.
struct NeverPrompter: ApprovalPrompter {
    func decide(_ request: ApprovalRequest) async -> ApprovalDecision {
        try? await Task.sleep(for: .seconds(3600))
        return .deny
    }
}
