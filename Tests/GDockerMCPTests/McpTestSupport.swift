import Darwin
import Foundation
import GDockerCore
import GDockerMCP

/// Minimal Docker for the MCP tests: one container, everything else a no-op.
struct StubDocker: DockerOperations {
    func listContainers() async throws -> [ContainerSummary] {
        [ContainerSummary(
            id: String(repeating: "a", count: 64), names: ["/web"], image: "nginx", state: "running",
            status: "Up 1 hour", labels: [:], ports: [])]
    }
    func inspect(_ id: String) async throws -> (details: ContainerDetails, rawJSON: String) { throw DockerError.notFound("stub") }
    func recentLogs(_ id: String, tail: Int, timestamps: Bool) async throws -> [LogLine] { [] }
    func statsOnce(_ id: String) async throws -> StatsSample { throw DockerError.notFound("stub") }
    func start(_ id: String) async throws {}
    func stop(_ id: String) async throws {}
    func restart(_ id: String) async throws {}
    func remove(_ id: String, force: Bool) async throws {}
    func exec(_ id: String, command: [String]) async throws -> ExecResult {
        ExecResult(exitCode: 0, stdout: "", stderr: "", truncated: false)
    }
}

actor ScriptedPrompter: ApprovalPrompter {
    private var decisions: [ApprovalDecision]
    private(set) var requests: [ApprovalRequest] = []

    init(_ decisions: [ApprovalDecision] = []) { self.decisions = decisions }

    func decide(_ request: ApprovalRequest) async -> ApprovalDecision {
        requests.append(request)
        return decisions.isEmpty ? .deny : decisions.removeFirst()
    }
}

actor TokenBox {
    private var value: String
    init(_ value: String) { self.value = value }
    func get() -> String { value }
    func set(_ value: String) { self.value = value }
}

/// A running server on a free port plus the pieces a test wants to poke at.
struct McpHarness {
    let server: McpHTTPServer
    let port: Int
    let permissions: PermissionStore
    let prompter: ScriptedPrompter
    let token: TokenBox

    var url: URL { URL(string: "http://127.0.0.1:\(port)/mcp")! }

    static func start(decisions: [ApprovalDecision] = [], token: String = "test-token") async throws -> McpHarness {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gdocker-mcp-\(UUID().uuidString)")
        let permissions = PermissionStore(fileURL: dir.appendingPathComponent("permissions.json"))
        let prompter = ScriptedPrompter(decisions)
        let router = ToolRouter(
            docker: { StubDocker() }, permissions: permissions, prompter: prompter,
            activity: ActivityLog(fileURL: dir.appendingPathComponent("activity.jsonl")))
        let box = TokenBox(token)
        let server = McpHTTPServer(router: router, token: { await box.get() }, requestedPort: 0)
        let port = try await server.start()
        return McpHarness(server: server, port: port, permissions: permissions, prompter: prompter, token: box)
    }

    func client(token: String? = "test-token") -> McpTestClient { McpTestClient(url: url, token: token) }
}

struct McpResponse {
    let status: Int
    let headers: [String: String]
    let messages: [[String: Any]]

    func header(_ name: String) -> String? { headers.first { $0.key.lowercased() == name.lowercased() }?.value }
    var result: [String: Any]? { messages.first?["result"] as? [String: Any] }
}

/// Speaks Streamable HTTP: POSTs JSON-RPC, remembers the session id, and reads JSON or SSE replies.
final class McpTestClient: @unchecked Sendable {
    let url: URL
    var token: String?
    var sessionID: String?
    var clientName = "test-client"

    init(url: URL, token: String?) { self.url = url; self.token = token }

    @discardableResult
    func post(_ body: [String: Any], headers: [String: String] = [:]) async throws -> McpResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let sessionID { request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id") }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = try unwrap(response as? HTTPURLResponse)
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields { headers["\(key)"] = "\(value)" }
        return McpResponse(status: http.statusCode, headers: headers, messages: Self.messages(in: data, headers: headers))
    }

    func initialize() async throws -> McpResponse {
        let response = try await post([
            "jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": ["protocolVersion": "2025-03-26", "capabilities": [:],
                       "clientInfo": ["name": clientName, "version": "1.0"]],
        ])
        sessionID = response.header("Mcp-Session-Id")
        if response.status == 200 {
            try await post(["jsonrpc": "2.0", "method": "notifications/initialized"])
        }
        return response
    }

    func call(_ tool: String, _ arguments: [String: Any] = [:], id: Int = 2) async throws -> McpResponse {
        try await post(["jsonrpc": "2.0", "id": id, "method": "tools/call",
                        "params": ["name": tool, "arguments": arguments]])
    }

    private static func messages(in data: Data, headers: [String: String]) -> [[String: Any]] {
        let text = String(decoding: data, as: UTF8.self)
        let isSSE = headers.contains { $0.key.lowercased() == "content-type" && $0.value.contains("text/event-stream") }
        let payloads = isSSE
            ? text.split(separator: "\n").compactMap { line -> String? in
                line.hasPrefix("data:") ? String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces) : nil
            }
            : [text]
        return payloads.compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
    }
}

func unwrap<T>(_ value: T?) throws -> T {
    guard let value else { throw McpTestError.missing }
    return value
}

enum McpTestError: Error { case missing, socket(String) }

/// A raw HTTP/1.1 request over a socket, for headers URLSession refuses to set (`Host`). `closed` is whether the
/// server closed the connection (as `Connection: close` asks) within the read timeout.
func rawRequest(port: Int, headers: [String: String], body: String) throws -> (status: Int, closed: Bool) {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { throw McpTestError.socket("socket") }
    defer { close(fd) }
    var timeout = timeval(tv_sec: 3, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    var address = sockaddr_in()
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = in_port_t(port).bigEndian
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    let connected = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
    }
    guard connected == 0 else { throw McpTestError.socket("connect") }
    var request = "POST /mcp HTTP/1.1\r\n"
    for (name, value) in headers { request += "\(name): \(value)\r\n" }
    request += "Content-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
    _ = request.withCString { send(fd, $0, strlen($0), 0) }
    var received = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    var closed = false
    while true {
        let count = recv(fd, &buffer, buffer.count, 0)
        if count == 0 { closed = true; break }
        if count < 0 { break }
        received.append(contentsOf: buffer[0..<count])
    }
    let statusLine = String(decoding: received, as: UTF8.self).split(separator: "\r\n").first ?? ""
    return (Int(statusLine.split(separator: " ").dropFirst().first ?? "") ?? -1, closed)
}
