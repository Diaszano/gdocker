import AsyncHTTPClient
import Foundation
import NIOCore

public struct ExecResult: Sendable, Equatable {
    public let exitCode: Int
    public let stdout: String
    public let stderr: String
    public let truncated: Bool

    public init(exitCode: Int, stdout: String, stderr: String, truncated: Bool) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.truncated = truncated
    }
}

extension DockerClient {
    /// Overload with the default limits. A default-valued parameter list alone does not satisfy
    /// `DockerOperations.exec(_:command:)`, so this forwards explicitly.
    public func exec(_ id: String, command: [String]) async throws -> ExecResult {
        try await exec(id, command: command, timeout: .seconds(60), outputLimit: 65_536)
    }

    /// Runs `command` (an argument list, no shell) in a running container. Each of stdout and stderr is cut at
    /// `outputLimit` bytes; the rest is read and dropped so the process can finish.
    public func exec(
        _ id: String, command: [String], timeout: Duration = .seconds(60), outputLimit: Int = 65_536
    ) async throws -> ExecResult {
        try await withThrowingTaskGroup(of: ExecResult.self) { group in
            group.addTask { try await self.runExec(id, command: command, outputLimit: outputLimit) }
            group.addTask {
                // shortcut: a timeout stops waiting but the process keeps running in the container;
                // killing it needs an exec-kill API Docker does not have, so upgrade by wrapping in `timeout` if needed
                try await Task.sleep(for: timeout)
                throw DockerError.transport("exec timed out after \(timeout.components.seconds) s")
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw DockerError.transport("exec produced no result") }
            return first
        }
    }

    private func runExec(_ id: String, command: [String], outputLimit: Int) async throws -> ExecResult {
        let created = try await send(
            .POST, "/containers/\(Self.pathSegment(id))/exec",
            json: ["AttachStdout": true, "AttachStderr": true, "Tty": false, "Cmd": command])
        guard let execID = (try JSONSerialization.jsonObject(with: created) as? [String: Any])?["Id"] as? String
        else { throw DockerError.transport("exec: unexpected response from Docker") }

        var request = self.request(.POST, "/exec/\(Self.pathSegment(execID))/start")
        try Self.attach(["Detach": false, "Tty": false], to: &request)
        let response = try await execute(request, timeout: .hours(1))
        try await Self.requireOK(response)

        var reader = FrameReader()
        var stdout: [UInt8] = []
        var stderr: [UInt8] = []
        var truncated = false
        for try await chunk in response.body {
            for frame in reader.feed(Array(chunk.readableBytesView)) {
                switch frame.stream {
                case .stdout: truncated = Self.append(frame.payload, to: &stdout, limit: outputLimit) || truncated
                case .stderr: truncated = Self.append(frame.payload, to: &stderr, limit: outputLimit) || truncated
                }
            }
        }
        return ExecResult(
            exitCode: try await exitCode(ofExec: execID),
            stdout: String(decoding: stdout, as: UTF8.self),
            stderr: String(decoding: stderr, as: UTF8.self),
            truncated: truncated)
    }

    /// The exit code is only reported once `Running` is false, which can lag the end of the output stream slightly.
    private func exitCode(ofExec execID: String) async throws -> Int {
        for _ in 0..<40 {
            let data = try await send(.GET, "/exec/\(Self.pathSegment(execID))/json")
            let info = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            if info["Running"] as? Bool != true { return info["ExitCode"] as? Int ?? -1 }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw DockerError.transport("exec did not report an exit code")
    }

    /// Appends up to the limit; returns whether anything was dropped.
    private static func append(_ payload: [UInt8], to buffer: inout [UInt8], limit: Int) -> Bool {
        let room = max(0, limit - buffer.count)
        buffer += payload.prefix(room)
        return payload.count > room
    }
}
