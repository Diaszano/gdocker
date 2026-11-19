import Testing

@testable import GDockerCore

@Suite("DockerCLITests")
struct DockerCLITests {

    @Test func candidatePathsAreInOrderWithHomeExpanded() {
        #expect(
            DockerCLI.candidatePaths(home: "/Users/u") == [
                "/usr/local/bin/docker",
                "/opt/homebrew/bin/docker",
                "/Users/u/.orbstack/bin/docker",
                "/Users/u/.rd/bin/docker",
                "/Applications/Docker.app/Contents/Resources/bin/docker",
                "/usr/bin/docker",
            ])
    }

    @Test func resolveReturnsFirstExisting() {
        let existing: Set = ["/opt/homebrew/bin/docker", "/usr/bin/docker"]
        #expect(DockerCLI.resolve(home: "/Users/u", fileExists: existing.contains) == "/opt/homebrew/bin/docker")
    }

    @Test func resolveIgnoresComposePlugin() {
        let existing: Set = ["/Users/u/.docker/cli-plugins/docker-compose"]
        #expect(DockerCLI.resolve(home: "/Users/u", fileExists: existing.contains) == nil)
    }

    @Test func environmentAddsUnixPrefix() {
        let base = ["PATH": "/usr/bin"]
        #expect(
            DockerCLI.environment(base: base, socketPath: "/var/run/docker.sock")["DOCKER_HOST"]
                == "unix:///var/run/docker.sock")
        #expect(DockerCLI.environment(base: base, socketPath: "unix:///x.sock")["DOCKER_HOST"] == "unix:///x.sock")
        #expect(DockerCLI.environment(base: base, socketPath: nil) == base)
    }

    @Test func terminalArgumentsExact() {
        #expect(
            DockerCLI.terminalArguments(containerID: "abc123") == [
                "exec", "-it", "abc123", "/bin/sh", "-c",
                "command -v bash >/dev/null 2>&1 && exec bash || exec sh",
            ])
    }

    @Test func exitCodeDecodesRawWaitStatus() {
        #expect(DockerCLI.exitCode(waitStatus: 0) == 0)
        #expect(DockerCLI.exitCode(waitStatus: 768) == 3)  // exit 3
        #expect(DockerCLI.exitCode(waitStatus: 32512) == 127)  // exit 127: command not found (distroless)
        #expect(DockerCLI.exitCode(waitStatus: 15) == 143)  // killed by SIGTERM → 128 + 15, as shells report it
    }

    @Test func availabilityFromState() {
        #expect(TerminalAvailability(state: "running") == .ready)
        #expect(TerminalAvailability(state: "paused") == .paused)
        #expect(TerminalAvailability(state: "restarting") == .restarting)
        for state in ["exited", "created", "dead"] {
            #expect(TerminalAvailability(state: state) == .stopped)
        }
    }
}
