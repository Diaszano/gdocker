import Foundation
import GDockerCore
import GDockerMCP
import Testing

nonisolated(unsafe) private let initialize: [String: Any] = [
    "jsonrpc": "2.0", "id": 1, "method": "initialize",
    "params": ["protocolVersion": "2025-03-26", "capabilities": [:],
               "clientInfo": ["name": "t", "version": "1"]],
]

// MARK: - Review focus 1: authentication and origin

@Test func noTokenIsRejected401() async throws {
    let h = try await McpHarness.start()
    let response = try await h.client(token: nil).post(initialize)
    #expect(response.status == 401)
    #expect(response.header("WWW-Authenticate")?.hasPrefix("Bearer") == true)
    await h.server.stop()
}

@Test func wrongTokenIsRejected401() async throws {
    let h = try await McpHarness.start()
    #expect(try await h.client(token: "nope").post(initialize).status == 401)
    #expect(try await h.client(token: "test-toke").post(initialize).status == 401)
    await h.server.stop()
}

@Test func unauthenticatedRequestNeverReachesATool() async throws {
    let h = try await McpHarness.start(decisions: [.allowOnce])
    let client = h.client(token: nil)
    let response = try await client.call("stop_container", ["container": "web"])
    #expect(response.status == 401)
    #expect(await h.prompter.requests.isEmpty)
    await h.server.stop()
}

@Test func nonLocalOriginIsRejected403() async throws {
    let h = try await McpHarness.start()
    let response = try await h.client().post(initialize, headers: ["Origin": "http://evil.example"])
    #expect(response.status == 403)
    await h.server.stop()
}

@Test func nonLocalHostIsRejected() async throws {
    let h = try await McpHarness.start()
    let body = String(decoding: try JSONSerialization.data(withJSONObject: initialize), as: UTF8.self)
    let result = try rawRequest(
        port: h.port,
        headers: ["Host": "evil.example", "Authorization": "Bearer test-token",
                  "Content-Type": "application/json", "Accept": "application/json, text/event-stream"],
        body: body)
    #expect([403, 421].contains(result.status), "got \(result.status)")
    #expect(result.closed, "the server kept the connection open after `Connection: close`")
    await h.server.stop()
}

@Test func tokenRegenerationTakesEffectImmediately() async throws {
    let h = try await McpHarness.start()
    let client = h.client()
    #expect(try await client.initialize().status == 200)
    await h.token.set("new-token")
    let stale = try await client.post(["jsonrpc": "2.0", "id": 5, "method": "tools/list"])
    #expect(stale.status == 401)
    client.token = "new-token"
    let fresh = try await client.post(["jsonrpc": "2.0", "id": 6, "method": "tools/list"])
    #expect(fresh.status == 200)
    await h.server.stop()
}

// MARK: - Tools over the wire

@Test func toolsListMatchesCatalog() async throws {
    let h = try await McpHarness.start()
    let client = h.client()
    #expect(try await client.initialize().status == 200)
    let response = try await client.post(["jsonrpc": "2.0", "id": 2, "method": "tools/list"])
    let tools = try unwrap(response.result?["tools"] as? [[String: Any]])
    #expect(Set(tools.compactMap { $0["name"] as? String }) == Set(ToolCatalog.all.map(\.name)))
    for tool in tools {
        let schema = try unwrap(tool["inputSchema"] as? [String: Any])
        let properties = try unwrap(schema["properties"] as? [String: Any])
        #expect(properties["reason"] != nil, "\(tool["name"] ?? "?") has no reason")
    }
    await h.server.stop()
}

@Test func callAllowedToolReturnsContent() async throws {
    let h = try await McpHarness.start()
    let client = h.client()
    #expect(try await client.initialize().status == 200)
    let response = try await client.call("list_containers")
    let result = try unwrap(response.result)
    #expect(result["isError"] as? Bool != true)
    let text = (try unwrap(result["content"] as? [[String: Any]]).first?["text"] as? String) ?? ""
    #expect(text.contains("web"))
    await h.server.stop()
}

@Test func callDeniedToolIsErrorResult() async throws {
    let h = try await McpHarness.start(decisions: [.allowOnce])
    try await h.permissions.set(.deny, for: "remove_container")
    let client = h.client()
    #expect(try await client.initialize().status == 200)
    let response = try await client.call("remove_container", ["container": "web"])
    let result = try unwrap(response.result)
    #expect(result["isError"] as? Bool == true)
    let text = (try unwrap(result["content"] as? [[String: Any]]).first?["text"] as? String) ?? ""
    #expect(text.contains("Blocked"))
    #expect(await h.prompter.requests.isEmpty)
    await h.server.stop()
}

@Test func clientNameReachesApprovalRequest() async throws {
    let h = try await McpHarness.start(decisions: [.deny])
    let client = h.client()
    client.clientName = "Claude Code"
    #expect(try await client.initialize().status == 200)
    _ = try await client.call("stop_container", ["container": "web", "reason": "investigating"])
    let request = try unwrap(await h.prompter.requests.first)
    #expect(request.client == "Claude Code")
    #expect(request.tool == "stop_container")
    #expect(request.reason == "investigating")
    await h.server.stop()
}

@Test func clientCountTracksSessions() async throws {
    let h = try await McpHarness.start()
    #expect(await h.server.clientCount() == 0)
    #expect(try await h.client().initialize().status == 200)
    #expect(await h.server.clientCount() == 1)
    #expect(try await h.client().initialize().status == 200)
    #expect(await h.server.clientCount() == 2)
    await h.server.stop()
}

// MARK: - Lifecycle

@Test func startFailsWhenPortInUse() async throws {
    let first = try await McpHarness.start()
    let second = McpHTTPServer(
        router: ToolRouter(
            docker: { nil }, permissions: PermissionStore(fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("gd-\(UUID().uuidString)/p.json")),
            prompter: ScriptedPrompter(),
            activity: ActivityLog(fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("gd-\(UUID().uuidString)/a.jsonl"))),
        token: { "x" }, requestedPort: first.port)
    await #expect(throws: McpServerError.portInUse(first.port)) { try await second.start() }
    await first.server.stop()
}

@Test func stopClosesTheListener() async throws {
    let h = try await McpHarness.start()
    #expect(try await h.client().initialize().status == 200)
    await h.server.stop()
    await #expect(throws: (any Error).self) { try await h.client().post(initialize) }
}
