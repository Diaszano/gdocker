import Foundation

@testable import GDockerCore

/// A throwaway alpine container for integration tests. Always removed, even when the body throws.
enum ScratchContainer {
    struct Failure: Error { let output: String }

    static let available: Bool = DockerSocket.discover() != nil && run(["--version"]).code == 0

    static func with<T>(_ body: (String) async throws -> T) async throws -> T {
        let name = "gd-test-\(UUID().uuidString.prefix(8).lowercased())"
        let started = run([
            "run", "-d", "--name", name, "alpine", "sh", "-c",
            "echo one; echo two; echo three; sleep 300",
        ])
        guard started.code == 0 else { throw Failure(output: started.output) }
        do {
            let result = try await body(name)
            _ = run(["rm", "-f", name])
            return result
        } catch {
            _ = run(["rm", "-f", name])
            throw error
        }
    }

    @discardableResult
    static func run(_ arguments: [String]) -> (code: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["docker"] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (-1, "\(error)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
