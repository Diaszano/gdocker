import AsyncHTTPClient
import Foundation
import NIOCore
import NIOHTTP1

public actor DockerClient {
    static let apiVersion = "v1.41"

    private let http: HTTPClient
    private let baseURL: String

    public init(socketPath: String) {
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

    public func listContainers() async throws -> [ContainerSummary] {
        let data = try await send(.GET, "/containers/json?all=1")
        return try JSONDecoder().decode([ContainerSummary].self, from: data)
    }

    public func inspect(_ id: String) async throws -> (details: ContainerDetails, rawJSON: String) {
        let data = try await send(.GET, "/containers/\(Self.pathSegment(id))/json")
        let details = try JSONDecoder().decode(ContainerDetails.self, from: data)
        let object = try JSONSerialization.jsonObject(with: data)
        let pretty = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        return (details, String(decoding: pretty, as: UTF8.self))
    }

    public func start(_ id: String) async throws { _ = try await send(.POST, "/containers/\(Self.pathSegment(id))/start") }
    public func stop(_ id: String) async throws { _ = try await send(.POST, "/containers/\(Self.pathSegment(id))/stop") }
    public func restart(_ id: String) async throws {
        _ = try await send(.POST, "/containers/\(Self.pathSegment(id))/restart")
    }

    public func remove(_ id: String, force: Bool) async throws {
        _ = try await send(.DELETE, "/containers/\(Self.pathSegment(id))?force=\(force)")
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

    private func send(_ method: HTTPMethod, _ path: String) async throws -> Data {
        let response = try await execute(request(method, path))
        let buffer = try await response.body.collect(upTo: 64 * 1024 * 1024)
        let data = Data(buffer.readableBytesView)
        if let error = DockerError.from(status: Int(response.status.code), body: data) { throw error }
        return data
    }
}
