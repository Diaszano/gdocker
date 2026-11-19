import Foundation
import Testing
@testable import GDockerCore

@Suite("ComposeRunnerTests")
struct ComposeRunnerTests {

    // MARK: - FakeComposeRunner Tests

    @Test func fakeRunnerRecordsCallsAndReturnsCannedOutputs() async throws {
        let fake = FakeComposeRunner(cannedUp: "Up ok", cannedDown: "Down ok")

        let isAvailable = await fake.isComposeAvailable()
        #expect(isAvailable == true)

        let upResult = try await fake.composeUp(
            project: "web-stack",
            workingDir: "/app",
            configFiles: ["docker-compose.yml"]
        )
        #expect(upResult == "Up ok")

        let downResult = try await fake.composeDown(
            project: "web-stack",
            workingDir: "/app",
            configFiles: ["docker-compose.yml"],
            removeVolumes: true
        )
        #expect(downResult == "Down ok")

        let calls = await fake.calls
        #expect(calls == [
            .up(project: "web-stack", workingDir: "/app", configFiles: ["docker-compose.yml"]),
            .down(project: "web-stack", workingDir: "/app", configFiles: ["docker-compose.yml"], removeVolumes: true)
        ])
    }

    @Test func fakeRunnerThrowsSimulatedErrors() async throws {
        let fake = FakeComposeRunner(error: ComposeError.binaryNotFound)

        await #expect(throws: ComposeError.binaryNotFound) {
            try await fake.composeUp(project: "proj", workingDir: "/app", configFiles: [])
        }

        await #expect(throws: ComposeError.binaryNotFound) {
            try await fake.composeDown(project: "proj", workingDir: "/app", configFiles: [], removeVolumes: false)
        }
    }

    // MARK: - CLIComposeRunner Discovery & Availability

    @Test func cliThrowsBinaryNotFoundWhenNoBinaryExists() async throws {
        let runner = CLIComposeRunner(
            binaryPath: nil,
            fileExists: { _ in false }
        )

        let available = await runner.isComposeAvailable()
        #expect(available == false)

        await #expect(throws: ComposeError.binaryNotFound) {
            try await runner.composeUp(
                project: "proj",
                workingDir: "/app",
                configFiles: ["compose.yml"]
            )
        }

        await #expect(throws: ComposeError.binaryNotFound) {
            try await runner.composeDown(
                project: "proj",
                workingDir: "/app",
                configFiles: ["compose.yml"],
                removeVolumes: false
            )
        }
    }

    @Test func cliResolvesBinaryFromKnownCandidates() async throws {
        let runner = CLIComposeRunner(
            binaryPath: nil,
            fileExists: { path in
                path == "/opt/homebrew/bin/docker"
            }
        )

        let available = await runner.isComposeAvailable()
        #expect(available == true)
    }

    // MARK: - Directory Validation (Review Focus 1)

    @Test func cliThrowsDirectoryNotFoundWhenWorkingDirDoesNotExist() async throws {
        let runner = CLIComposeRunner(
            binaryPath: "/usr/local/bin/docker",
            fileExists: { path in
                path == "/usr/local/bin/docker" // workingDir is missing
            }
        )

        await #expect(throws: ComposeError.directoryNotFound("/missing/dir")) {
            try await runner.composeUp(
                project: "proj",
                workingDir: "/missing/dir",
                configFiles: ["compose.yml"]
            )
        }

        await #expect(throws: ComposeError.directoryNotFound("/missing/dir")) {
            try await runner.composeDown(
                project: "proj",
                workingDir: "/missing/dir",
                configFiles: ["compose.yml"],
                removeVolumes: false
            )
        }
    }

    // MARK: - Argument Building (Review Focus 2)

    @Test func cliBuildsCorrectArgumentsForComposeUp() async throws {
        final class Captured: @unchecked Sendable {
            var binary: String?
            var args: [String] = []
            var dir: String?
        }
        let captured = Captured()

        let runner = CLIComposeRunner(
            binaryPath: "/usr/local/bin/docker",
            fileExists: { _ in true },
            processLauncher: { binary, args, _, dir in
                captured.binary = binary
                captured.args = args
                captured.dir = dir
                return (0, "Container web Started\n")
            }
        )

        let output = try await runner.composeUp(
            project: "my-stack",
            workingDir: "/workspace/project",
            configFiles: ["docker-compose.yml", "docker-compose.override.yml"]
        )

        #expect(output == "Container web Started\n")
        #expect(captured.binary == "/usr/local/bin/docker")
        #expect(captured.dir == "/workspace/project")
        #expect(captured.args == [
            "compose",
            "-f", "docker-compose.yml",
            "-f", "docker-compose.override.yml",
            "--project-directory", "/workspace/project",
            "-p", "my-stack",
            "up",
            "-d"
        ])
    }

    @Test func cliBuildsCorrectArgumentsForComposeDownWithoutAndWithVolumeRemoval() async throws {
        final class Captured: @unchecked Sendable {
            var args: [String] = []
        }
        let captured = Captured()

        let runner = CLIComposeRunner(
            binaryPath: "/usr/local/bin/docker",
            fileExists: { _ in true },
            processLauncher: { _, args, _, _ in
                captured.args = args
                return (0, "Removed\n")
            }
        )

        // Down without volume removal
        _ = try await runner.composeDown(
            project: "my-stack",
            workingDir: "/workspace/project",
            configFiles: ["docker-compose.yml"],
            removeVolumes: false
        )

        #expect(captured.args == [
            "compose",
            "-f", "docker-compose.yml",
            "--project-directory", "/workspace/project",
            "-p", "my-stack",
            "down"
        ])

        // Down with volume removal (-v)
        _ = try await runner.composeDown(
            project: "my-stack",
            workingDir: "/workspace/project",
            configFiles: ["docker-compose.yml"],
            removeVolumes: true
        )

        #expect(captured.args == [
            "compose",
            "-f", "docker-compose.yml",
            "--project-directory", "/workspace/project",
            "-p", "my-stack",
            "down",
            "-v"
        ])
    }

    // MARK: - Environment & DOCKER_HOST

    @Test func cliSetsDockerHostEnvironmentVariable() async throws {
        final class Captured: @unchecked Sendable {
            var env: [String: String] = [:]
        }
        let captured = Captured()

        let runner = CLIComposeRunner(
            binaryPath: "/usr/local/bin/docker",
            socketPath: "/custom/run/docker.sock",
            environment: ["ORIGINAL_VAR": "val"],
            fileExists: { _ in true },
            processLauncher: { _, _, env, _ in
                captured.env = env
                return (0, "")
            }
        )

        _ = try await runner.composeUp(
            project: "proj",
            workingDir: "/app",
            configFiles: []
        )

        #expect(captured.env["DOCKER_HOST"] == "unix:///custom/run/docker.sock")
        #expect(captured.env["ORIGINAL_VAR"] == "val")
    }

    // MARK: - Error Handling & Stderr Parsing (Review Focus 5)

    @Test func cliParsesExitCodeAndOutputOnFailure() async throws {
        let runner = CLIComposeRunner(
            binaryPath: "/usr/local/bin/docker",
            fileExists: { _ in true },
            processLauncher: { _, _, _, _ in
                return (1, "Error: bind: address already in use\n")
            }
        )

        do {
            _ = try await runner.composeUp(
                project: "proj",
                workingDir: "/app",
                configFiles: ["compose.yml"]
            )
            Issue.record("Expected composeUp to throw commandFailed")
        } catch let ComposeError.commandFailed(exitCode, output) {
            #expect(exitCode == 1)
            #expect(output.contains("address already in use"))
        } catch {
            Issue.record("Unexpected error thrown: \(error)")
        }
    }

    @Test func composeFallsBackToPluginWhenNoDocker() async throws {
        final class Captured: @unchecked Sendable { var binary: String?; var args: [String] = [] }
        let captured = Captured()
        let plugin = NSHomeDirectory() + "/.docker/cli-plugins/docker-compose"
        let runner = CLIComposeRunner(
            fileExists: { $0 == plugin || $0 == "/workspace" },
            processLauncher: { binary, args, _, _ in
                captured.binary = binary
                captured.args = args
                return (0, "")
            }
        )
        #expect(await runner.isComposeAvailable())
        _ = try await runner.composeUp(project: "p", workingDir: "/workspace", configFiles: [])
        #expect(captured.binary == plugin)
        #expect(captured.args.first != "compose")
    }

    @Test func composeFindsOrbStackDocker() async throws {
        final class Captured: @unchecked Sendable { var binary: String?; var args: [String] = [] }
        let captured = Captured()
        let orbstack = NSHomeDirectory() + "/.orbstack/bin/docker"
        let runner = CLIComposeRunner(
            fileExists: { $0 == orbstack || $0 == "/workspace" },
            processLauncher: { binary, args, _, _ in
                captured.binary = binary
                captured.args = args
                return (0, "")
            }
        )
        #expect(await runner.isComposeAvailable())
        _ = try await runner.composeUp(project: "p", workingDir: "/workspace", configFiles: [])
        #expect(captured.binary == orbstack)
        #expect(captured.args.first == "compose")
    }

    @Test func composeFindsRancherDesktopDocker() async throws {
        final class Captured: @unchecked Sendable { var binary: String?; var args: [String] = [] }
        let captured = Captured()
        let rancher = NSHomeDirectory() + "/.rd/bin/docker"
        let runner = CLIComposeRunner(
            fileExists: { $0 == rancher || $0 == "/workspace" },
            processLauncher: { binary, args, _, _ in
                captured.binary = binary
                captured.args = args
                return (0, "")
            }
        )
        #expect(await runner.isComposeAvailable())
        _ = try await runner.composeUp(project: "p", workingDir: "/workspace", configFiles: [])
        #expect(captured.binary == rancher)
        #expect(captured.args.first == "compose")
    }

    @Test func composeErrorDescriptions() {
        let binaryErr = ComposeError.binaryNotFound
        #expect(binaryErr.errorDescription?.contains("not found") == true)

        let dirErr = ComposeError.directoryNotFound("/nonexistent/path")
        #expect(dirErr.errorDescription == "Directory '/nonexistent/path' does not exist")

        let cmdErr = ComposeError.commandFailed(exitCode: 2, output: "daemon error")
        #expect(cmdErr.errorDescription?.contains("2") == true)
        #expect(cmdErr.errorDescription?.contains("daemon error") == true)
    }
}
