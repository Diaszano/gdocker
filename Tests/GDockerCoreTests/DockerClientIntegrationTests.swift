import Foundation
import Testing
@testable import GDockerCore

private let hasDocker = DockerSocket.discover() != nil

/// AsyncHTTPClient crashes if a client is dropped without shutdown, so always shut down, even on failure.
private func withClient<T: Sendable>(_ body: (DockerClient) async throws -> T) async throws -> T {
    let client = try DockerClient.connect()
    do {
        let result = try await body(client)
        await client.shutdown()
        return result
    } catch {
        await client.shutdown()
        throw error
    }
}

@Suite(.enabled(if: hasDocker)) struct DockerClientIntegrationTests {
    @Test func pingSucceeds() async throws {
        try await withClient { try await $0.ping() }
    }

    @Test func listContainersSucceeds() async throws {
        _ = try await withClient { try await $0.listContainers() }
    }

    @Test func logsOfAnExistingContainerDecode() async throws {
        let lines = try await withClient { client -> [LogLine] in
            guard let target = try await client.listContainers().first else { return [] }
            let tty = try await client.inspect(target.id).details.config.tty
            var collected: [LogLine] = []
            for try await batch in await client.logs(target.id, tty: tty, follow: false, tail: 5, timestamps: true) {
                collected += batch
            }
            return collected
        }
        #expect(lines.count <= 5)
        #expect(lines.allSatisfy { $0.timestamp != nil })
    }

    @Test func inspectMissingContainerIsNotFound() async throws {
        await #expect {
            try await withClient { _ = try await $0.inspect("gdocker-nope-\(UUID().uuidString)") }
        } throws: { error in
            guard case .notFound = error as? DockerError else { return false }
            return true
        }
    }
}
