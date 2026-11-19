import Foundation
import Testing

@testable import GDockerCore

private func frame(_ stream: UInt8, _ text: String) -> [UInt8] {
    let payload = Array(text.utf8)
    let n = UInt32(payload.count)
    return [stream, 0, 0, 0, UInt8(n >> 24), UInt8((n >> 16) & 0xFF), UInt8((n >> 8) & 0xFF), UInt8(n & 0xFF)] + payload
}

@Test func frameReaderReturnsAFrameSplitAcrossFeeds() {
    let bytes = frame(2, "oops\n")
    var reader = FrameReader()
    var frames: [(stream: LogLine.Stream, payload: [UInt8])] = []
    frames += reader.feed(Array(bytes[0..<3]))
    frames += reader.feed(Array(bytes[3..<10]))
    #expect(frames.isEmpty)
    frames += reader.feed(Array(bytes[10...]))
    #expect(frames.count == 1)
    #expect(frames[0].stream == .stderr)
    #expect(String(decoding: frames[0].payload, as: UTF8.self) == "oops\n")
}

@Suite(.enabled(if: ScratchContainer.available)) struct ExecTests {
    @Test func execCapturesStdoutAndExitZero() async throws {
        try await ScratchContainer.with { name in
            let result = try await withClient { try await $0.exec(name, command: ["echo", "hello"]) }
            #expect(result == ExecResult(exitCode: 0, stdout: "hello\n", stderr: "", truncated: false))
        }
    }

    @Test func execCapturesStderrAndExitCode() async throws {
        try await ScratchContainer.with { name in
            let result = try await withClient {
                try await $0.exec(name, command: ["sh", "-c", "echo err 1>&2; exit 3"])
            }
            #expect(result.stderr == "err\n")
            #expect(result.stdout == "")
            #expect(result.exitCode == 3)
        }
    }

    @Test func execArgvIsNotAShell() async throws {
        try await ScratchContainer.with { name in
            let result = try await withClient { try await $0.exec(name, command: ["echo", "$HOME"]) }
            #expect(result.stdout == "$HOME\n")
        }
    }

    @Test func execTruncatesHugeOutput() async throws {
        try await ScratchContainer.with { name in
            let result = try await withClient {
                try await $0.exec(
                    name, command: ["sh", "-c", "head -c 200000 /dev/zero | tr '\\0' x"],
                    timeout: .seconds(30), outputLimit: 1000)
            }
            #expect(result.stdout.utf8.count <= 1000)
            #expect(result.truncated)
        }
    }

    @Test func execTimesOut() async throws {
        try await ScratchContainer.with { name in
            await #expect {
                try await withClient {
                    try await $0.exec(name, command: ["sleep", "5"], timeout: .seconds(1), outputLimit: 1000)
                }
            } throws: { error in
                if case .transport = error as? DockerError { return true }
                return false
            }
        }
    }
}

@Test(.enabled(if: DockerSocket.discover() != nil)) func execOnMissingContainerIsNotFound() async throws {
    await #expect {
        try await withClient { try await $0.exec("gdocker-nope-\(UUID().uuidString)", command: ["echo"]) }
    } throws: { error in
        if case .notFound = error as? DockerError { return true }
        return false
    }
}
