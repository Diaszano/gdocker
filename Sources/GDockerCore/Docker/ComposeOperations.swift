import Foundation

/// Defines high-level Docker Compose operations supported by GDocker.
public protocol ComposeOperations: Sendable {
    func composeUp(project: String, workingDir: String, configFiles: [String]) async throws -> String
    func composeDown(project: String, workingDir: String, configFiles: [String], removeVolumes: Bool) async throws -> String
    func isComposeAvailable() async -> Bool
}

/// Errors thrown by Docker Compose runners.
public enum ComposeError: LocalizedError, Sendable, Equatable {
    case binaryNotFound
    case directoryNotFound(String)
    case commandFailed(exitCode: Int32, output: String)

    public var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "Docker CLI binary not found"
        case .directoryNotFound(let dir):
            return "Directory '\(dir)' does not exist"
        case .commandFailed(let exitCode, let output):
            return "Docker compose failed with exit code \(exitCode): \(output)"
        }
    }
}

/// In-memory fake implementation of `ComposeOperations` for unit and integration testing.
public actor FakeComposeRunner: ComposeOperations {
    public enum Call: Sendable, Equatable {
        case up(project: String, workingDir: String, configFiles: [String])
        case down(project: String, workingDir: String, configFiles: [String], removeVolumes: Bool)
    }

    public private(set) var calls: [Call] = []
    public var isAvailable: Bool
    public var upResponse: Result<String, any Error>
    public var downResponse: Result<String, any Error>

    public init(
        isAvailable: Bool = true,
        cannedUp: String = "Started",
        cannedDown: String = "Stopped",
        error: (any Error)? = nil
    ) {
        self.isAvailable = isAvailable
        if let error {
            self.upResponse = .failure(error)
            self.downResponse = .failure(error)
        } else {
            self.upResponse = .success(cannedUp)
            self.downResponse = .success(cannedDown)
        }
    }

    public init(
        isAvailable: Bool = true,
        upResponse: Result<String, any Error>,
        downResponse: Result<String, any Error>
    ) {
        self.isAvailable = isAvailable
        self.upResponse = upResponse
        self.downResponse = downResponse
    }

    public func setUpResponse(_ result: Result<String, any Error>) {
        self.upResponse = result
    }

    public func setDownResponse(_ result: Result<String, any Error>) {
        self.downResponse = result
    }

    public func setIsAvailable(_ available: Bool) {
        self.isAvailable = available
    }

    public func composeUp(project: String, workingDir: String, configFiles: [String]) async throws -> String {
        calls.append(.up(project: project, workingDir: workingDir, configFiles: configFiles))
        return try upResponse.get()
    }

    public func composeDown(project: String, workingDir: String, configFiles: [String], removeVolumes: Bool) async throws -> String {
        calls.append(.down(project: project, workingDir: workingDir, configFiles: configFiles, removeVolumes: removeVolumes))
        return try downResponse.get()
    }

    public func isComposeAvailable() async -> Bool {
        isAvailable
    }
}

/// Official Docker CLI-backed implementation of `ComposeOperations`.
public final class CLIComposeRunner: ComposeOperations, Sendable {
    public typealias ProcessLauncher = @Sendable (
        _ executable: String,
        _ arguments: [String],
        _ environment: [String: String],
        _ currentDirectory: String?
    ) async throws -> (exitCode: Int32, output: String)

    public let binaryPath: String?
    public let socketPath: String?
    public let environment: [String: String]
    public let fileExists: @Sendable (String) -> Bool
    public let processLauncher: ProcessLauncher?

    public init(
        binaryPath: String? = nil,
        socketPath: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        processLauncher: ProcessLauncher? = nil
    ) {
        self.binaryPath = binaryPath
        self.socketPath = socketPath
        self.environment = environment
        self.fileExists = fileExists
        self.processLauncher = processLauncher
    }

    private var candidateBinaryPaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let expandedTilde = (home as NSString).appendingPathComponent(".docker/cli-plugins/docker-compose")
        return [
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            "~/.docker/cli-plugins/docker-compose",
            expandedTilde,
            "/usr/bin/docker",
        ]
    }

    private func resolveBinaryPath() -> String? {
        if let binaryPath {
            let expanded = (binaryPath as NSString).expandingTildeInPath
            if fileExists(binaryPath) { return binaryPath }
            if fileExists(expanded) { return expanded }
            return nil
        }
        for candidate in candidateBinaryPaths {
            if fileExists(candidate) {
                return candidate
            }
        }
        return nil
    }

    private func resolveSocketPath() -> String? {
        if let socketPath { return socketPath }
        return DockerSocket.discover(env: environment, exists: fileExists)
    }

    public func isComposeAvailable() async -> Bool {
        resolveBinaryPath() != nil
    }

    private func buildArguments(
        binary: String,
        project: String,
        workingDir: String,
        configFiles: [String],
        command: String,
        extraFlags: [String] = []
    ) -> [String] {
        var args: [String] = []
        if !binary.hasSuffix("docker-compose") {
            args.append("compose")
        }
        for file in configFiles {
            args.append("-f")
            args.append(file)
        }
        args.append(contentsOf: ["--project-directory", workingDir, "-p", project, command])
        args.append(contentsOf: extraFlags)
        return args
    }

    public func composeUp(project: String, workingDir: String, configFiles: [String]) async throws -> String {
        guard let binary = resolveBinaryPath() else {
            throw ComposeError.binaryNotFound
        }
        guard fileExists(workingDir) else {
            throw ComposeError.directoryNotFound(workingDir)
        }

        let args = buildArguments(
            binary: binary,
            project: project,
            workingDir: workingDir,
            configFiles: configFiles,
            command: "up",
            extraFlags: ["-d"]
        )
        return try await execute(binary: binary, arguments: args, workingDir: workingDir)
    }

    public func composeDown(
        project: String,
        workingDir: String,
        configFiles: [String],
        removeVolumes: Bool
    ) async throws -> String {
        guard let binary = resolveBinaryPath() else {
            throw ComposeError.binaryNotFound
        }
        guard fileExists(workingDir) else {
            throw ComposeError.directoryNotFound(workingDir)
        }

        let args = buildArguments(
            binary: binary,
            project: project,
            workingDir: workingDir,
            configFiles: configFiles,
            command: "down",
            extraFlags: removeVolumes ? ["-v"] : []
        )
        return try await execute(binary: binary, arguments: args, workingDir: workingDir)
    }

    private func execute(binary: String, arguments: [String], workingDir: String) async throws -> String {
        var env = environment
        if let socket = resolveSocketPath() {
            let host = socket.hasPrefix("unix://") ? socket : "unix://\(socket)"
            env["DOCKER_HOST"] = host
        }

        let result: (exitCode: Int32, output: String)
        if let processLauncher {
            result = try await processLauncher(binary, arguments, env, workingDir)
        } else {
            result = await defaultLaunchProcess(
                executable: (binary as NSString).expandingTildeInPath,
                arguments: arguments,
                environment: env,
                currentDirectory: workingDir
            )
        }

        guard result.exitCode == 0 else {
            throw ComposeError.commandFailed(exitCode: result.exitCode, output: result.output)
        }

        return result.output
    }

    private func defaultLaunchProcess(
        executable: String,
        arguments: [String],
        environment: [String: String],
        currentDirectory: String?
    ) async -> (exitCode: Int32, output: String) {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.environment = environment
            if let currentDirectory {
                process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
            }
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
            } catch {
                return (-1, "\(error)")
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(decoding: data, as: UTF8.self))
        }.value
    }
}
