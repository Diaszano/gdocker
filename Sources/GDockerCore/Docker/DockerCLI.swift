import Foundation

/// Locating and invoking the `docker` command-line tool, for the features that need it (Compose, Terminal).
public enum DockerCLI {
    /// No `PATH` lookup: an app launched from Finder gets a minimal `PATH`, so it would not find more than this list.
    public static func candidatePaths(home: String) -> [String] {
        [
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            "\(home)/.orbstack/bin/docker",
            "\(home)/.rd/bin/docker",
            "/Applications/Docker.app/Contents/Resources/bin/docker",
            "/usr/bin/docker",
        ]
    }

    public static func resolve(home: String = NSHomeDirectory(), fileExists: (String) -> Bool) -> String? {
        candidatePaths(home: home).first(where: fileExists)
    }

    public static func environment(base: [String: String], socketPath: String?) -> [String: String] {
        guard let socketPath else { return base }
        var env = base
        env["DOCKER_HOST"] = socketPath.hasPrefix("unix://") ? socketPath : "unix://\(socketPath)"
        return env
    }

    /// Opens bash when the image has it, otherwise sh.
    public static func terminalArguments(containerID: String) -> [String] {
        ["exec", "-it", containerID, "/bin/sh", "-c", "command -v bash >/dev/null 2>&1 && exec bash || exec sh"]
    }

    /// Turns a raw `waitpid` status into the code a shell would report: the exit status, or 128 + signal.
    public static func exitCode(waitStatus status: Int32) -> Int32 {
        let signal = status & 0x7f
        return signal == 0 ? (status >> 8) & 0xff : 128 + signal
    }
}

/// Whether a terminal session can open for a container, by its state. `docker exec` only works on `running`.
public enum TerminalAvailability: Equatable, Sendable {
    case ready, stopped, paused, restarting

    public init(state: String) {
        switch state {
        case "running": self = .ready
        case "paused": self = .paused
        case "restarting": self = .restarting
        default: self = .stopped
        }
    }
}
