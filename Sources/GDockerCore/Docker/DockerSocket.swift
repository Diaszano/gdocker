import CryptoKit
import Foundation

public enum DockerSocket {
    /// Finds the Docker socket: DOCKER_HOST, then the current docker context, then well-known paths.
    public static func discover(
        env: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> String? {
        if let path = unixPath(env["DOCKER_HOST"]), exists(path) { return path }
        if let path = contextSocket(home: home), exists(path) { return path }
        let known = [
            "/var/run/docker.sock",
            home.appendingPathComponent(".docker/run/docker.sock").path,
            home.appendingPathComponent(".orbstack/run/docker.sock").path,
            home.appendingPathComponent(".colima/default/docker.sock").path,
            home.appendingPathComponent(".rd/docker.sock").path,
        ]
        return known.first(where: exists)
    }

    private static func unixPath(_ host: String?) -> String? {
        guard let host, host.hasPrefix("unix://") else { return nil }
        return String(host.dropFirst("unix://".count))
    }

    private static func contextSocket(home: URL) -> String? {
        let docker = home.appendingPathComponent(".docker")
        guard let config = readJSON(docker.appendingPathComponent("config.json")),
            let name = config["currentContext"] as? String, name != "default"
        else { return nil }
        let hash = SHA256.hash(data: Data(name.utf8)).map { String(format: "%02x", $0) }.joined()
        let meta = readJSON(docker.appendingPathComponent("contexts/meta/\(hash)/meta.json"))
        let endpoints = meta?["Endpoints"] as? [String: Any]
        let dockerEndpoint = endpoints?["docker"] as? [String: Any]
        return unixPath(dockerEndpoint?["Host"] as? String)
    }

    private static func readJSON(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
