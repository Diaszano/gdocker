import CryptoKit
import Foundation
import Testing
@testable import GDockerCore

private func tempHome() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("gdocker-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test func envUnixWins() throws {
    let path = DockerSocket.discover(env: ["DOCKER_HOST": "unix:///tmp/x.sock"], home: try tempHome(), exists: { _ in true })
    #expect(path == "/tmp/x.sock")
}

@Test func envTcpIgnored() throws {
    let path = DockerSocket.discover(
        env: ["DOCKER_HOST": "tcp://1.2.3.4:2375"], home: try tempHome(), exists: { $0 == "/var/run/docker.sock" })
    #expect(path == "/var/run/docker.sock")
}

@Test func contextResolved() throws {
    let home = try tempHome()
    let docker = home.appendingPathComponent(".docker")
    let hash = SHA256.hash(data: Data("colima".utf8)).map { String(format: "%02x", $0) }.joined()
    let metaDir = docker.appendingPathComponent("contexts/meta/\(hash)")
    try FileManager.default.createDirectory(at: metaDir, withIntermediateDirectories: true)
    try Data(#"{"currentContext":"colima"}"#.utf8).write(to: docker.appendingPathComponent("config.json"))
    try Data(#"{"Endpoints":{"docker":{"Host":"unix:///h/.colima/default/docker.sock"}}}"#.utf8)
        .write(to: metaDir.appendingPathComponent("meta.json"))
    let path = DockerSocket.discover(env: [:], home: home, exists: { $0 == "/h/.colima/default/docker.sock" })
    #expect(path == "/h/.colima/default/docker.sock")
}

@Test func knownPathFallback() throws {
    let home = try tempHome()
    let orb = home.appendingPathComponent(".orbstack/run/docker.sock").path
    let path = DockerSocket.discover(env: [:], home: home, exists: { $0 == orb })
    #expect(path == orb)
}

@Test func nothingFound() throws {
    #expect(DockerSocket.discover(env: [:], home: try tempHome(), exists: { _ in false }) == nil)
}
