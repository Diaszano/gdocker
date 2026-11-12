/// What the MCP tool router needs from Docker. A protocol so tests can use a fake.
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
}

extension DockerClient: DockerOperations {}
