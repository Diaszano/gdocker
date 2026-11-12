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
        let data = try await send(.GET, "/containers/\(id)/json")
        let details = try JSONDecoder().decode(ContainerDetails.self, from: data)
        let object = try JSONSerialization.jsonObject(with: data)
        let pretty = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        return (details, String(decoding: pretty, as: UTF8.self))
    }

    public func start(_ id: String) async throws { _ = try await send(.POST, "/containers/\(id)/start") }
    public func stop(_ id: String) async throws { _ = try await send(.POST, "/containers/\(id)/stop") }
    public func restart(_ id: String) async throws { _ = try await send(.POST, "/containers/\(id)/restart") }

    public func remove(_ id: String, force: Bool) async throws {
        _ = try await send(.DELETE, "/containers/\(id)?force=\(force)")
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
