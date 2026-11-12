import Foundation
import GDockerCore
import GDockerMCP
import Testing

/// Feeds `lines` to a bridge through pipes, waits for it to finish at EOF, and returns what it wrote.
private func runBridge(
    _ lines: [String], endpoint: @escaping @Sendable () -> URL?, token: @escaping @Sendable () throws -> String? = { "test-token" }
) async throws -> [[String: Any]] {
    let input = Pipe()
    let output = Pipe()
    let bridge = StdioBridge(endpoint: endpoint, token: token)
    let finished = Task { await bridge.run(input: input.fileHandleForReading, output: output.fileHandleForWriting) }
    for line in lines { try input.fileHandleForWriting.write(contentsOf: Data((line + "\n").utf8)) }
    try input.fileHandleForWriting.close()
    await finished.value
    try output.fileHandleForWriting.close()
    let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    return try text.split(separator: "\n").map { line in
        try unwrap(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
    }
}

private let initialize = #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"bridge-test","version":"1"}}}"#
private let initialized = #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#
private let toolsList = #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#

private func errorCode(_ message: [String: Any]) -> Int? { (message["error"] as? [String: Any])?["code"] as? Int }

@Test func bridgesInitializeAndToolsList() async throws {
    let h = try await McpHarness.start()
    let url = h.url
    let out = try await runBridge([initialize, initialized, toolsList], endpoint: { url })
    #expect(out.count == 2)
    #expect(Set(out.compactMap { $0["id"] as? Int }) == [1, 2])
    let list = try unwrap(out.first { $0["id"] as? Int == 2 })
    let tools = try unwrap((list["result"] as? [String: Any])?["tools"] as? [[String: Any]])
    #expect(tools.contains { $0["name"] as? String == "list_containers" })
    await h.server.stop()
}

@Test func bridgesAToolCall() async throws {
    let h = try await McpHarness.start()
    let url = h.url
    let call = #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list_containers","arguments":{}}}"#
    let out = try await runBridge([initialize, initialized, call], endpoint: { url })
    let reply = try unwrap(out.first { $0["id"] as? Int == 3 })
    let content = try unwrap((reply["result"] as? [String: Any])?["content"] as? [[String: Any]])
    #expect((content.first?["text"] as? String)?.contains("web") == true)
    await h.server.stop()
}

@Test func deadEndpointAnswersWithErrorAndSameId() async throws {
    let dead = URL(string: "http://127.0.0.1:1/mcp")!
    let out = try await runBridge([#"{"jsonrpc":"2.0","id":"abc","method":"tools/list"}"#], endpoint: { dead })
    #expect(out.count == 1)
    #expect(out[0]["id"] as? String == "abc")
    #expect(errorCode(out[0]) == -32000)
    #expect(((out[0]["error"] as? [String: Any])?["message"] as? String)?.contains("not running") == true)
}

@Test func missingEndpointAnswersLikeANotRunningApp() async throws {
    let out = try await runBridge([toolsList], endpoint: { nil })
    #expect(errorCode(try unwrap(out.first)) == -32000)
}

@Test func notificationWithDeadEndpointProducesNoOutput() async throws {
    let dead = URL(string: "http://127.0.0.1:1/mcp")!
    let out = try await runBridge([initialized], endpoint: { dead })
    #expect(out.isEmpty)
}

@Test func wrongTokenAnswersWithAuthError() async throws {
    let h = try await McpHarness.start()
    let url = h.url
    let out = try await runBridge([initialize], endpoint: { url }, token: { "bad-token" })
    #expect(out[0]["id"] as? Int == 1)
    #expect(errorCode(out[0]) == -32001)
    await h.server.stop()
}

@Test func missingTokenAnswersWithAuthErrorWithoutCallingTheServer() async throws {
    let h = try await McpHarness.start()
    let url = h.url
    let out = try await runBridge([initialize], endpoint: { url }, token: { nil })
    #expect(errorCode(try unwrap(out.first)) == -32001)
    #expect(await h.server.clientCount() == 0)
    await h.server.stop()
}

@Test func endingTheBridgeClosesItsSession() async throws {
    let h = try await McpHarness.start()
    let url = h.url
    _ = try await runBridge([initialize, initialized, toolsList], endpoint: { url })
    #expect(await h.server.clientCount() == 0)
    await h.server.stop()
}
