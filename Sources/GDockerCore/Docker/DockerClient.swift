import AsyncHTTPClient
import Foundation
import NIOCore
import NIOHTTP1

public actor DockerClient {
    static let apiVersion = "v1.41"

    private let http: HTTPClient
    private let baseURL: String
    nonisolated public let socketPath: String

    public init(socketPath: String) {
        self.socketPath = socketPath
        let host = socketPath.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? socketPath
        baseURL = "http+unix://\(host)/\(Self.apiVersion)"
        http = HTTPClient(eventLoopGroupProvider: .singleton)
    }

    /// Container ids and names can come from an MCP client, so they must not be able to add `/`, `?` or `#` to a URL.
    static func pathSegment(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    public static func connect() throws -> DockerClient {
        guard let path = DockerSocket.discover() else { throw DockerError.socketNotFound }
        return DockerClient(socketPath: path)
    }

    public func shutdown() async {
        try? await http.shutdown()
    }

    public func ping() async throws {
        _ = try await send(.GET, "/_ping")
    }

    public func hostInfo() async throws -> DockerHostInfo {
        struct RawInfo: Decodable {
            let name: String?
            let ncpu: Int?
            let memTotal: Int64?
            enum CodingKeys: String, CodingKey {
                case name = "Name"
                case ncpu = "NCPU"
                case memTotal = "MemTotal"
            }
        }
        struct RawDF: Decodable {
            let layersSize: Int64?
            enum CodingKeys: String, CodingKey { case layersSize = "LayersSize" }
        }

        let infoData = try await send(.GET, "/info")
        let raw = try JSONDecoder().decode(RawInfo.self, from: infoData)
        let isColima =
            socketPath.lowercased().contains("colima")
            || (raw.name?.lowercased().contains("colima") ?? false)

        var diskUsed: Int64?
        if let dfData = try? await send(.GET, "/system/df"),
            let df = try? JSONDecoder().decode(RawDF.self, from: dfData)
        {
            diskUsed = df.layersSize
        }

        var diskTotal: Int64?
        if isColima, let colimaDisk = await Self.readColimaDiskBytes() {
            diskTotal = colimaDisk
        }

        return DockerHostInfo(
            name: raw.name ?? (isColima ? "Colima" : "Docker"),
            cpus: raw.ncpu ?? 0,
            memTotal: raw.memTotal ?? 0,
            diskUsed: diskUsed,
            diskTotal: diskTotal,
            isColima: isColima
        )
    }

    /// Aggregates CPU % and memory used across running containers using one-shot stats.
    public func hostUsage(runningIDs: [String]) async -> (cpuPercent: Double?, memUsed: Int64?) {
        guard !runningIDs.isEmpty else { return (0, 0) }
        return await withTaskGroup(of: (Double, Int64)?.self) { group in
            for id in runningIDs {
                group.addTask {
                    guard
                        let data = try? await self.send(.GET, "/containers/\(Self.pathSegment(id))/stats?stream=false"),
                        let sample = try? StatsSample.from(json: data)
                    else {
                        return nil
                    }
                    return (sample.cpuPercent, Int64(clamping: sample.memoryUsed))
                }
            }
            var totalCPU = 0.0
            var totalMem: Int64 = 0
            var count = 0
            for await item in group {
                if let (cpu, mem) = item {
                    totalCPU += cpu
                    totalMem += mem
                    count += 1
                }
            }
            return count > 0 ? (totalCPU, totalMem) : (nil, nil)
        }
    }

    private static func readColimaDiskBytes() async -> Int64? {
        await Task.detached(priority: .utility) {
            struct ColimaStatus: Decodable { let disk: Int64? }
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["colima", "status", "--json"]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { return nil }
                return try? JSONDecoder().decode(ColimaStatus.self, from: data).disk
            } catch {
                return nil
            }
        }.value
    }

    public func listContainers() async throws -> [ContainerSummary] {
        let data = try await send(.GET, "/containers/json?all=1&size=1")
        return try JSONDecoder().decode([ContainerSummary].self, from: data)
    }

    public func inspect(_ id: String) async throws -> (details: ContainerDetails, rawJSON: String) {
        let data = try await send(.GET, "/containers/\(Self.pathSegment(id))/json")
        let details = try JSONDecoder().decode(ContainerDetails.self, from: data)
        let object = try JSONSerialization.jsonObject(with: data)
        let pretty = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        return (details, String(decoding: pretty, as: UTF8.self))
    }

    public func start(_ id: String) async throws {
        _ = try await send(.POST, "/containers/\(Self.pathSegment(id))/start")
    }
    public func stop(_ id: String) async throws {
        _ = try await send(.POST, "/containers/\(Self.pathSegment(id))/stop")
    }
    public func restart(_ id: String) async throws {
        _ = try await send(.POST, "/containers/\(Self.pathSegment(id))/restart")
    }

    public func remove(_ id: String, force: Bool) async throws {
        _ = try await send(.DELETE, "/containers/\(Self.pathSegment(id))?force=\(force)")
    }

    // MARK: - Images

    public func listImages() async throws -> [ImageSummary] {
        let data = try await send(.GET, "/images/json")
        return try JSONDecoder().decode([ImageSummary].self, from: data)
    }

    public func removeImage(_ id: String, force: Bool = false) async throws {
        _ = try await send(.DELETE, "/images/\(Self.pathSegment(id))?force=\(force)")
    }

    public func pruneImages(all: Bool = false) async throws -> (deleted: [String], spaceReclaimed: Int64) {
        let query = all ? "?filters=%7B%22dangling%22%3A%5B%22false%22%5D%7D" : ""
        let data = try await send(.POST, "/images/prune\(query)")
        let res = try JSONDecoder().decode(ImagePruneResponse.self, from: data)
        return (deleted: res.deletedItems, spaceReclaimed: res.spaceReclaimed ?? 0)
    }

    // MARK: - Volumes

    public func listVolumes() async throws -> [VolumeSummary] {
        let data = try await send(.GET, "/volumes")
        let res = try JSONDecoder().decode(VolumesResponse.self, from: data)
        return res.volumes ?? []
    }

    public func removeVolume(_ name: String, force: Bool = false) async throws {
        _ = try await send(.DELETE, "/volumes/\(Self.pathSegment(name))?force=\(force)")
    }

    public func pruneVolumes() async throws -> (deleted: [String], spaceReclaimed: Int64) {
        let data = try await send(.POST, "/volumes/prune")
        let res = try JSONDecoder().decode(VolumePruneResponse.self, from: data)
        return (deleted: res.volumesDeleted ?? [], spaceReclaimed: res.spaceReclaimed ?? 0)
    }

    // MARK: - Networks

    public func listNetworks() async throws -> [NetworkSummary] {
        let data = try await send(.GET, "/networks")
        return try JSONDecoder().decode([NetworkSummary].self, from: data)
    }

    public func removeNetwork(_ id: String) async throws {
        _ = try await send(.DELETE, "/networks/\(Self.pathSegment(id))")
    }

    public func pruneNetworks() async throws -> [String] {
        let data = try await send(.POST, "/networks/prune")
        let res = try JSONDecoder().decode(NetworkPruneResponse.self, from: data)
        return res.networksDeleted ?? []
    }

    // MARK: - Containers Prune

    public func pruneContainers() async throws -> (deleted: [String], spaceReclaimed: Int64) {
        let data = try await send(.POST, "/containers/prune")
        let res = try JSONDecoder().decode(ContainerPruneResponse.self, from: data)
        return (deleted: res.containersDeleted ?? [], spaceReclaimed: res.spaceReclaimed ?? 0)
    }

    /// The last `tail` log lines, without following.
    public func recentLogs(_ id: String, tail: Int, timestamps: Bool) async throws -> [LogLine] {
        let tty = try await inspect(id).details.config.tty
        var lines: [LogLine] = []
        for try await batch in logs(id, tty: tty, follow: false, tail: tail, timestamps: timestamps) {
            lines += batch
        }
        return lines
    }

    /// One stats sample. The stream's first sample has no previous CPU reading, so this waits for the second.
    public func statsOnce(_ id: String) async throws -> StatsSample {
        for try await sample in stats(id) { return sample }
        throw DockerError.conflict("container is not running")
    }

    /// Streams log lines in batches. Cancelling the consumer cancels the HTTP request.
    public func logs(
        _ id: String, tty: Bool, follow: Bool, tail: Int = 500, timestamps: Bool
    ) -> AsyncThrowingStream<[LogLine], Error> {
        let query = "stdout=1&stderr=1&follow=\(follow)&tail=\(tail)&timestamps=\(timestamps)"
        let request = request(.GET, "/containers/\(Self.pathSegment(id))/logs?\(query)")
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    // shortcut: a followed stream is capped at one year; reconnect logic is not worth it before that
                    let response = try await self.execute(request, timeout: follow ? .hours(24 * 365) : .seconds(60))
                    try await Self.requireOK(response)
                    var demuxer = LogDemuxer(tty: tty, timestamps: timestamps)
                    for try await chunk in response.body {
                        let lines = demuxer.feed(Array(chunk.readableBytesView))
                        if !lines.isEmpty { continuation.yield(lines) }
                    }
                    let rest = demuxer.flush()
                    if !rest.isEmpty { continuation.yield(rest) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Streams stats samples, skipping the first one (no previous CPU reading yet).
    public func stats(_ id: String) -> AsyncThrowingStream<StatsSample, Error> {
        let request = request(.GET, "/containers/\(Self.pathSegment(id))/stats?stream=1")
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let response = try await self.execute(request, timeout: .hours(24 * 365))
                    try await Self.requireOK(response)
                    var pending = Data()
                    for try await chunk in response.body {
                        pending.append(contentsOf: chunk.readableBytesView)
                        while let newline = pending.firstIndex(of: 0x0A) {
                            let line = pending[..<newline]
                            pending.removeSubrange(...newline)
                            if let sample = try StatsSample.from(json: Data(line)) { continuation.yield(sample) }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func attach(_ json: [String: Any], to request: inout HTTPClientRequest) throws {
        request.headers.add(name: "Content-Type", value: "application/json")
        request.body = .bytes(try JSONSerialization.data(withJSONObject: json))
    }

    static func requireOK(_ response: HTTPClientResponse) async throws {
        guard response.status.code != 200 else { return }
        let body = try await response.body.collect(upTo: 1024 * 1024)
        let status = Int(response.status.code)
        throw DockerError.from(status: status, body: Data(body.readableBytesView))
            ?? .server(status: status, message: "unexpected status \(status)")
    }

    // MARK: - Transport

    func request(_ method: HTTPMethod, _ path: String) -> HTTPClientRequest {
        var request = HTTPClientRequest(url: baseURL + path)
        request.method = method
        // AsyncHTTPClient sends no Host header over a unix socket and the Docker daemon rejects that with 400.
        request.headers.add(name: "Host", value: "localhost")
        return request
    }

    func execute(_ request: HTTPClientRequest, timeout: TimeAmount = .seconds(60)) async throws -> HTTPClientResponse {
        do {
            return try await http.execute(request, timeout: timeout)
        } catch {
            throw DockerError.transport(String(describing: error))
        }
    }

    func send(_ method: HTTPMethod, _ path: String, json: [String: Any]? = nil) async throws -> Data {
        var request = self.request(method, path)
        if let json { try Self.attach(json, to: &request) }
        let response = try await execute(request)
        let buffer = try await response.body.collect(upTo: 64 * 1024 * 1024)
        let data = Data(buffer.readableBytesView)
        if let error = DockerError.from(status: Int(response.status.code), body: data) { throw error }
        return data
    }
}

// MARK: - Internal Response Payloads

struct ImagePruneResponse: Decodable {
    struct Item: Decodable {
        let untagged: String?
        let deleted: String?
        enum CodingKeys: String, CodingKey {
            case untagged = "Untagged"
            case deleted = "Deleted"
        }
    }
    let imagesDeleted: [Item]?
    let spaceReclaimed: Int64?

    enum CodingKeys: String, CodingKey {
        case imagesDeleted = "ImagesDeleted"
        case spaceReclaimed = "SpaceReclaimed"
    }

    var deletedItems: [String] {
        imagesDeleted?.compactMap { $0.deleted ?? $0.untagged } ?? []
    }
}

struct VolumesResponse: Decodable {
    let volumes: [VolumeSummary]?
    enum CodingKeys: String, CodingKey {
        case volumes = "Volumes"
    }
}

struct VolumePruneResponse: Decodable {
    let volumesDeleted: [String]?
    let spaceReclaimed: Int64?
    enum CodingKeys: String, CodingKey {
        case volumesDeleted = "VolumesDeleted"
        case spaceReclaimed = "SpaceReclaimed"
    }
}

struct NetworkPruneResponse: Decodable {
    let networksDeleted: [String]?
    enum CodingKeys: String, CodingKey {
        case networksDeleted = "NetworksDeleted"
    }
}

struct ContainerPruneResponse: Decodable {
    let containersDeleted: [String]?
    let spaceReclaimed: Int64?
    enum CodingKeys: String, CodingKey {
        case containersDeleted = "ContainersDeleted"
        case spaceReclaimed = "SpaceReclaimed"
    }
}
