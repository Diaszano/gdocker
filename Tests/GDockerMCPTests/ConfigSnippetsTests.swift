import Foundation
import GDockerMCP
import Testing

private let url = URL(string: "http://127.0.0.1:7391/mcp")!

private func servers(_ json: String) throws -> [String: Any] {
    let object = try unwrap(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    return try unwrap((object["mcpServers"] as? [String: Any])?["gdocker"] as? [String: Any])
}

@Test func claudeCodeCommandHasUrlAndBearerHeader() {
    #expect(
        McpConfigSnippets.claudeCode(url: url, token: "abc123")
            == #"claude mcp add --transport http gdocker http://127.0.0.1:7391/mcp --header "Authorization: Bearer abc123""#
    )
}

@Test func jsonHTTPIsValidAndCarriesUrlAndToken() throws {
    let text = McpConfigSnippets.jsonHTTP(url: url, token: "abc123")
    let entry = try servers(text)
    #expect(entry["type"] as? String == "http")
    #expect(entry["url"] as? String == "http://127.0.0.1:7391/mcp")
    #expect((entry["headers"] as? [String: String])?["Authorization"] == "Bearer abc123")
    #expect(!text.contains("\\/"), "slashes must not be escaped so the snippet stays readable")
}

@Test func desktopStdioPointsAtTheExecutableWithStdioFlag() throws {
    let path = "/Applications/GDocker.app/Contents/MacOS/GDocker"
    let text = McpConfigSnippets.claudeDesktopStdio(executable: path)
    let entry = try servers(text)
    #expect(entry["command"] as? String == path)
    #expect(entry["args"] as? [String] == ["--stdio"])
    #expect(!text.contains("\\/"))
    #expect(!text.contains("Bearer"), "the stdio form reads the token itself and must not embed it")
}
