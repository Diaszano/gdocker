import Darwin
import Foundation
import GDockerCore
import MCP
import NIOCore
import NIOHTTP1
import NIOPosix

public enum McpServerError: Error, Equatable { case portInUse(Int) }

/// The MCP server: Streamable HTTP on 127.0.0.1, one SDK `Server` per client session, every tool call handed to the
/// `ToolRouter`. Every request must carry the bearer token; Host/Origin must be local (DNS rebinding).
public actor McpHTTPServer {
    private struct Session {
        let server: Server
        let transport: StatefulHTTPServerTransport
        var lastAccess: Date
    }

    private actor ClientName {
        private(set) var value = "unknown client"
        func set(_ name: String) { value = name }
    }

    private struct FixedSessionID: SessionIDGenerator {
        let id: String
        func generateSessionID() -> String { id }
    }

    private static let endpoint = "/mcp"
    private static let idleTimeout: TimeInterval = 3600

    private let router: ToolRouter
    private let token: @Sendable () async throws -> String
    private let requestedPort: Int
    private var group: MultiThreadedEventLoopGroup?
    private var channel: Channel?
    private var boundPort = 0
    private var sessions: [String: Session] = [:]
    private var cleanup: Task<Void, Never>?

    /// `token` is a closure so a regenerated token takes effect at the very next request.
    public init(router: ToolRouter, token: @escaping @Sendable () async throws -> String, requestedPort: Int = 7391) {
        self.router = router
        self.token = token
        self.requestedPort = requestedPort
    }

    /// Starts listening and returns the port actually bound (`requestedPort: 0` picks a free one).
    public func start() async throws -> Int {
        if channel != nil { return boundPort }
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 2)
        let handle: @Sendable (HTTPRequest) async -> HTTPResponse = { [weak self] request in
            guard let self else { return .error(statusCode: 503, .internalError("The server has stopped")) }
            return await self.handle(request)
        }
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 64)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(McpNIOHandler(path: Self.endpoint, handle: handle))
                }
            }
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)
        do {
            // Loopback only: the server must never be reachable from the network.
            let channel = try await bootstrap.bind(host: "127.0.0.1", port: requestedPort).get()
            self.group = group
            self.channel = channel
            boundPort = channel.localAddress?.port ?? requestedPort
        } catch {
            try? await group.shutdownGracefully()
            if (error as? IOError)?.errnoCode == EADDRINUSE { throw McpServerError.portInUse(requestedPort) }
            throw error
        }
        cleanup = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                await self?.expireIdleSessions()
            }
        }
        return boundPort
    }

    public func stop() async {
        cleanup?.cancel()
        cleanup = nil
        for id in Array(sessions.keys) { await close(id) }
        try? await channel?.close()
        channel = nil
        try? await group?.shutdownGracefully()
        group = nil
    }

    public func clientCount() -> Int { sessions.count }

    // MARK: - Requests

    private func handle(_ request: HTTPRequest) async -> HTTPResponse {
        guard await isAuthorized(request) else {
            return .error(
                statusCode: 401, .invalidRequest("Unauthorized: missing or invalid bearer token"),
                extraHeaders: [HTTPHeaderName.wwwAuthenticate: "Bearer"])
        }
        let sessionID = request.header(HTTPHeaderName.sessionID)
        if let sessionID, var session = sessions[sessionID] {
            session.lastAccess = Date()
            sessions[sessionID] = session
            let response = await session.transport.handleRequest(request)
            if request.method.uppercased() == "DELETE" && response.statusCode == 200 { await close(sessionID) }
            return response
        }
        if request.method.uppercased() == "POST", Self.isInitialize(request.body) {
            return await createSession(for: request)
        }
        if sessionID != nil {
            return .error(statusCode: 404, .invalidRequest("Not Found: Session not found or expired"))
        }
        return .error(statusCode: 400, .invalidRequest("Bad Request: Missing \(HTTPHeaderName.sessionID) header"))
    }

    /// Checked here rather than in the SDK's validator pipeline because those validators are synchronous and the
    /// token comes from an actor. Running it first also means an unauthenticated caller learns nothing else.
    private func isAuthorized(_ request: HTTPRequest) async -> Bool {
        guard let header = request.header(HTTPHeaderName.authorization), header.lowercased().hasPrefix("bearer ")
        else { return false }
        let presented = String(header.dropFirst("bearer ".count)).trimmingCharacters(in: .whitespaces)
        guard let expected = try? await token() else { return false }
        return tokensMatch(presented, expected)
    }

    private static func isInitialize(_ body: Data?) -> Bool {
        guard let body, let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return false
        }
        return object["method"] as? String == "initialize"
    }

    // MARK: - Sessions

    private func createSession(for request: HTTPRequest) async -> HTTPResponse {
        let id = UUID().uuidString
        let transport = StatefulHTTPServerTransport(
            sessionIDGenerator: FixedSessionID(id: id),
            validationPipeline: StandardValidationPipeline(validators: [
                OriginValidator.localhost(port: boundPort),
                AcceptHeaderValidator(mode: .sseRequired),
                ContentTypeValidator(),
                ProtocolVersionValidator(),
                SessionValidator(),
            ]))
        let name = ClientName()
        let server = await makeServer(clientName: name)
        do {
            try await server.start(transport: transport) { info, _ in await name.set(info.name) }
            sessions[id] = Session(server: server, transport: transport, lastAccess: Date())
            let response = await transport.handleRequest(request)
            if case .error = response { await close(id) }
            return response
        } catch {
            await transport.disconnect()
            return .error(statusCode: 500, .internalError("Failed to create session: \(error.localizedDescription)"))
        }
    }

    private func makeServer(clientName: ClientName) async -> Server {
        let server = Server(
            name: "gdocker",
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev",
            instructions: "Controls the user's local Docker through GDocker. The user can block each tool or require "
                + "approval; pass `reason` so they know why you are calling it.",
            capabilities: .init(tools: .init(listChanged: false)))
        let tools = ToolCatalog.all.map(Self.tool)
        await server.withMethodHandler(ListTools.self) { _ in .init(tools: tools) }
        let router = router
        await server.withMethodHandler(CallTool.self) { params in
            let output = await router.call(
                params.name, arguments: SchemaConversion.arguments(from: params.arguments),
                client: await clientName.value)
            return .init(content: [.text(text: output.text, annotations: nil, _meta: nil)], isError: output.isError)
        }
        return server
    }

    private static func tool(_ spec: ToolSpec) -> Tool {
        Tool(
            name: spec.name, title: spec.title, description: spec.summary,
            inputSchema: SchemaConversion.inputSchema(for: spec),
            annotations: Tool.Annotations(
                readOnlyHint: spec.group == .read || spec.group == .sensitiveRead,
                destructiveHint: spec.group == .destructive))
    }

    private func close(_ id: String) async {
        guard let session = sessions.removeValue(forKey: id) else { return }
        await session.transport.disconnect()
        await session.server.stop()
    }

    private func expireIdleSessions() async {
        let now = Date()
        for (id, session) in sessions where now.timeIntervalSince(session.lastAccess) > Self.idleTimeout {
            await close(id)
        }
    }
}
