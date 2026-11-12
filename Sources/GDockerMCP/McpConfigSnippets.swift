import Foundation

/// Ready-to-paste client configuration for the three ways a client can reach gdocker.
public enum McpConfigSnippets {
    /// Claude Code, over HTTP.
    public static func claudeCode(url: URL, token: String) -> String {
        #"claude mcp add --transport http gdocker \#(url.absoluteString) --header "Authorization: Bearer \#(token)""#
    }

    /// A generic `mcpServers` JSON entry, over HTTP.
    public static func jsonHTTP(url: URL, token: String) -> String {
        json(["mcpServers": ["gdocker": [
            "type": "http", "url": url.absoluteString, "headers": ["Authorization": "Bearer \(token)"],
        ] as [String: Any]]])
    }

    /// Claude Desktop, which only launches stdio servers. The bridge reads the token from the keychain itself, so the
    /// snippet carries none.
    public static func claudeDesktopStdio(executable: String) -> String {
        json(["mcpServers": ["gdocker": ["command": executable, "args": ["--stdio"]] as [String: Any]]])
    }

    private static func json(_ object: [String: Any]) -> String {
        let data = try? JSONSerialization.data(
            withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data ?? Data(), as: UTF8.self)
    }
}
