import Foundation
import Testing
@testable import GDockerCore

@Suite("VolumeWebDAVServiceTests")
struct VolumeWebDAVServiceTests {

    @Test func sanitizeDirectoryNameReplacesUnsafeCharacters() {
        #expect(VolumeWebDAVService.sanitizeDirectoryName("my-app_pgdata") == "my-app_pgdata")
        #expect(VolumeWebDAVService.sanitizeDirectoryName("foo/bar:baz") == "foo_bar_baz")
        #expect(VolumeWebDAVService.sanitizeDirectoryName("...") == "volume")
        #expect(VolumeWebDAVService.sanitizeDirectoryName("") == "volume")
    }

    @Test func containerNameHasExpectedPrefixAndSuffix() {
        let name = VolumeWebDAVService.containerName(for: "My/Volume", suffix: "abc123")
        #expect(name == "gdocker-webdav-my_volume-abc123")
    }

    @Test func dockerRunArgumentsBindToLocalhostAndMountVolume() {
        let args = VolumeWebDAVService.dockerRunArguments(
            volumeName: "pgdata",
            containerName: "gdocker-webdav-pgdata-1234",
            port: 49152
        )
        #expect(args == [
            "run", "-d", "--rm",
            "--name", "gdocker-webdav-pgdata-1234",
            "--label", "gdocker.webdav=true",
            "--label", "gdocker.webdav.volume=pgdata",
            "-p", "127.0.0.1:49152:8080",
            "-v", "pgdata:/data",
            "rclone/rclone:latest",
            "serve", "webdav", "/data", "--addr", ":8080",
        ])
    }

    @Test func mountWebDAVArgumentsUseSilentFlagAndVolumeName() {
        let args = VolumeWebDAVService.mountWebDAVArguments(
            volumeName: "pgdata",
            port: 49152,
            mountPoint: "/tmp/mnt/pgdata"
        )
        #expect(args == [
            "-S",
            "-v", "pgdata",
            "http://127.0.0.1:49152/",
            "/tmp/mnt/pgdata",
        ])
    }

    @Test func findFreePortReturnsValidEphemeralPort() throws {
        let port = try VolumeWebDAVService.findFreePort()
        #expect(port > 0)
    }

    @Test func isPathMountedIsFalseForRegularAndMissingDirectories() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gdocker-webdav-test-\(UUID().uuidString)", isDirectory: true)
        #expect(!VolumeWebDAVService.isPathMounted(tempDir))

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        #expect(!VolumeWebDAVService.isPathMounted(tempDir))
    }
}
