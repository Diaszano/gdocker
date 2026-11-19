import Foundation

/// Where the running app tells the `--stdio` bridge which URL to talk to.
public enum McpEndpoint {
    public static func fileURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GDocker/mcp-endpoint.json")
    }

    public static func write(_ url: URL, to file: URL = fileURL()) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(["url": url.absoluteString]).write(to: file, options: .atomic)
    }

    public static func read(from file: URL = fileURL()) -> URL? {
        guard let data = try? Data(contentsOf: file),
            let object = try? JSONDecoder().decode([String: String].self, from: data),
            let text = object["url"]
        else { return nil }
        return URL(string: text)
    }

    public static func remove(at file: URL = fileURL()) {
        try? FileManager.default.removeItem(at: file)
    }
}
