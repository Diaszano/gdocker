import Foundation

public struct VolumeMountInfo: Sendable, Equatable {
    public let volumeName: String
    public let containerName: String
    public let port: UInt16
    public let mountPoint: URL

    public init(volumeName: String, containerName: String, port: UInt16, mountPoint: URL) {
        self.volumeName = volumeName
        self.containerName = containerName
        self.port = port
        self.mountPoint = mountPoint
    }
}

public enum VolumeWebDAVError: LocalizedError, Equatable {
    case dockerCLIMissing
    case portAllocationFailed
    case dockerStartFailed(String)
    case serverTimedOut(String)
    case mountFailed(String)

    public var errorDescription: String? {
        switch self {
        case .dockerCLIMissing:
            return "Docker CLI was not found on this system."
        case .portAllocationFailed:
            return "Could not allocate a local port for the WebDAV server."
        case .dockerStartFailed(let detail):
            return "Failed to start WebDAV container: \(detail)"
        case .serverTimedOut(let detail):
            return "Timed out waiting for WebDAV server to become ready. \(detail)"
        case .mountFailed(let detail):
            return "Failed to mount WebDAV volume in Finder: \(detail)"
        }
    }
}

/// Manages temporary `rclone` WebDAV containers and macOS `mount_webdav` mounts for Docker volumes.
public final class VolumeWebDAVService: @unchecked Sendable {
    public static let shared = VolumeWebDAVService()
    public static let webdavImage = "rclone/rclone:latest"

    private let lock = NSLock()
    private var activeMounts: [String: VolumeMountInfo] = [:]
    private let baseMountsDirectory: URL

    public init(baseMountsDirectory: URL? = nil) {
        if let baseMountsDirectory {
            self.baseMountsDirectory = baseMountsDirectory
        } else {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            self.baseMountsDirectory = caches.appendingPathComponent("com.gdocker.volume-mounts", isDirectory: true)
        }
    }

    // MARK: - Pure Helpers

    public static func sanitizeDirectoryName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let sanitized = String(name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        let trimmed = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return trimmed.isEmpty ? "volume" : String(trimmed.prefix(80))
    }

    public static func containerName(for volumeName: String, suffix: String = String(UUID().uuidString.prefix(8)).lowercased()) -> String {
        let safe = sanitizeDirectoryName(volumeName)
            .lowercased()
            .replacingOccurrences(of: "..", with: "_")
        return "gdocker-webdav-\(String(safe.prefix(40)))-\(suffix)"
    }

    public static func dockerRunArguments(volumeName: String, containerName: String, port: UInt16) -> [String] {
        [
            "run", "-d", "--rm",
            "--name", containerName,
            "--label", "gdocker.webdav=true",
            "--label", "gdocker.webdav.volume=\(volumeName)",
            "-p", "127.0.0.1:\(port):8080",
            "-v", "\(volumeName):/data",
            webdavImage,
            "serve", "webdav", "/data", "--addr", ":8080",
        ]
    }

    public static func mountWebDAVArguments(volumeName: String, port: UInt16, mountPoint: String) -> [String] {
        [
            "-S",
            "-v", volumeName,
            "http://127.0.0.1:\(port)/",
            mountPoint,
        ]
    }

    /// Returns true when `url` is a mounted filesystem (different device ID than its parent directory).
    public static func isPathMounted(_ url: URL) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return false }
        let parent = url.deletingLastPathComponent()
        guard let childAttrs = try? fm.attributesOfItem(atPath: url.path),
              let parentAttrs = try? fm.attributesOfItem(atPath: parent.path),
              let childDev = childAttrs[.systemNumber] as? NSNumber,
              let parentDev = parentAttrs[.systemNumber] as? NSNumber
        else {
            return false
        }
        return childDev != parentDev
    }

    public static func findFreePort() throws -> UInt16 {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { throw VolumeWebDAVError.portAllocationFailed }
        defer { close(sock) }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { throw VolumeWebDAVError.portAllocationFailed }

        var boundAddr = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(sock, $0, &len)
            }
        }
        guard nameResult == 0 else { throw VolumeWebDAVError.portAllocationFailed }
        return UInt16(bigEndian: boundAddr.sin_port)
    }

    // MARK: - State

    public func mountedVolumeNames() -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return Set(activeMounts.keys)
    }

    public func mountInfo(for volumeName: String) -> VolumeMountInfo? {
        lock.lock()
        defer { lock.unlock() }
        return activeMounts[volumeName]
    }

    private func setMount(_ info: VolumeMountInfo) {
        lock.lock()
        activeMounts[info.volumeName] = info
        lock.unlock()
    }

    private func removeMountRecord(for volumeName: String) -> VolumeMountInfo? {
        lock.lock()
        defer { lock.unlock() }
        return activeMounts.removeValue(forKey: volumeName)
    }

    private func removeAllMountRecords() -> [VolumeMountInfo] {
        lock.lock()
        defer { lock.unlock() }
        let all = Array(activeMounts.values)
        activeMounts.removeAll()
        return all
    }

    // MARK: - Mount / Unmount

    public func mount(volumeName: String, socketPath: String?) async throws -> VolumeMountInfo {
        if let existing = mountInfo(for: volumeName),
           Self.isPathMounted(existing.mountPoint) {
            return existing
        }

        // Clean up any stale record if the mount disappeared (e.g. user ejected it in Finder).
        if let stale = removeMountRecord(for: volumeName) {
            await cleanupResources(mountPoint: stale.mountPoint, containerName: stale.containerName, socketPath: socketPath)
        }

        guard let dockerPath = DockerCLI.resolve(fileExists: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw VolumeWebDAVError.dockerCLIMissing
        }

        let port = try Self.findFreePort()
        let containerName = Self.containerName(for: volumeName)
        let mountPoint = baseMountsDirectory.appendingPathComponent(Self.sanitizeDirectoryName(volumeName), isDirectory: true)

        try prepareMountDirectory(at: mountPoint)

        let dockerEnv = DockerCLI.environment(base: ProcessInfo.processInfo.environment, socketPath: socketPath)
        let runArgs = Self.dockerRunArguments(volumeName: volumeName, containerName: containerName, port: port)

        let runResult = try await runProcess(executable: dockerPath, arguments: runArgs, environment: dockerEnv)
        guard runResult.exitCode == 0 else {
            try? FileManager.default.removeItem(at: mountPoint)
            let detail = runResult.stderr.isEmpty ? runResult.stdout : runResult.stderr
            throw VolumeWebDAVError.dockerStartFailed(detail.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        do {
            try await waitForWebDAVServer(port: port, containerName: containerName, dockerPath: dockerPath, environment: dockerEnv)
            let mountArgs = Self.mountWebDAVArguments(volumeName: volumeName, port: port, mountPoint: mountPoint.path)
            let mountResult = try await runProcess(executable: "/sbin/mount_webdav", arguments: mountArgs, environment: ProcessInfo.processInfo.environment)
            guard mountResult.exitCode == 0 else {
                let detail = mountResult.stderr.isEmpty ? mountResult.stdout : mountResult.stderr
                throw VolumeWebDAVError.mountFailed(detail.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        } catch {
            await cleanupResources(mountPoint: mountPoint, containerName: containerName, socketPath: socketPath)
            throw error
        }

        let info = VolumeMountInfo(volumeName: volumeName, containerName: containerName, port: port, mountPoint: mountPoint)
        setMount(info)
        return info
    }

    public func unmount(volumeName: String, socketPath: String?) async {
        guard let info = removeMountRecord(for: volumeName) else { return }
        await cleanupResources(mountPoint: info.mountPoint, containerName: info.containerName, socketPath: socketPath)
    }

    public func unmountAll(socketPath: String?) async {
        let mounts = removeAllMountRecords()
        for info in mounts {
            await cleanupResources(mountPoint: info.mountPoint, containerName: info.containerName, socketPath: socketPath)
        }
    }

    /// Synchronous cleanup suitable for `NSApplicationDelegate.applicationWillTerminate`.
    public func unmountAllSync(socketPath: String?) {
        let mounts = removeAllMountRecords()
        guard !mounts.isEmpty else { return }
        let dockerPath = DockerCLI.resolve(fileExists: { FileManager.default.isExecutableFile(atPath: $0) })
        let dockerEnv = DockerCLI.environment(base: ProcessInfo.processInfo.environment, socketPath: socketPath)

        for info in mounts {
            cleanupResourcesSync(mountPoint: info.mountPoint, containerName: info.containerName, dockerPath: dockerPath, dockerEnv: dockerEnv)
        }
    }

    // MARK: - Private Helpers

    private func prepareMountDirectory(at url: URL) throws {
        let fm = FileManager.default
        if Self.isPathMounted(url) {
            _ = runProcessSync(executable: "/sbin/umount", arguments: ["-f", url.path], environment: ProcessInfo.processInfo.environment)
        }
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func waitForWebDAVServer(
        port: UInt16,
        containerName: String,
        dockerPath: String,
        environment: [String: String]
    ) async throws {
        guard let url = URL(string: "http://127.0.0.1:\(port)/") else {
            throw VolumeWebDAVError.serverTimedOut("Invalid URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "OPTIONS"
        request.timeoutInterval = 1.0

        for attempt in 0..<60 {
            if attempt > 0 {
                try await Task.sleep(for: .milliseconds(250))
            }

            if let (_, response) = try? await URLSession.shared.data(for: request),
               let http = response as? HTTPURLResponse,
               (200..<500).contains(http.statusCode) {
                return
            }

            // Fail fast if the container already exited.
            if attempt % 4 == 3 {
                let inspect = try? await runProcess(
                    executable: dockerPath,
                    arguments: ["inspect", "-f", "{{.State.Running}}", containerName],
                    environment: environment
                )
                if let inspect, inspect.exitCode != 0 || inspect.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "false" {
                    let logs = try? await runProcess(executable: dockerPath, arguments: ["logs", containerName], environment: environment)
                    let detail = logs?.stderr.isEmpty == false ? logs!.stderr : (logs?.stdout ?? "")
                    throw VolumeWebDAVError.serverTimedOut(detail.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        }

        throw VolumeWebDAVError.serverTimedOut("WebDAV server did not respond on port \(port).")
    }

    private func cleanupResources(mountPoint: URL, containerName: String, socketPath: String?) async {
        let dockerPath = DockerCLI.resolve(fileExists: { FileManager.default.isExecutableFile(atPath: $0) })
        let dockerEnv = DockerCLI.environment(base: ProcessInfo.processInfo.environment, socketPath: socketPath)
        await Task.detached(priority: .utility) {
            self.cleanupResourcesSync(mountPoint: mountPoint, containerName: containerName, dockerPath: dockerPath, dockerEnv: dockerEnv)
        }.value
    }

    private func cleanupResourcesSync(
        mountPoint: URL,
        containerName: String,
        dockerPath: String?,
        dockerEnv: [String: String]
    ) {
        if Self.isPathMounted(mountPoint) {
            let result = runProcessSync(executable: "/sbin/umount", arguments: [mountPoint.path], environment: ProcessInfo.processInfo.environment)
            if result.exitCode != 0 {
                _ = runProcessSync(executable: "/sbin/umount", arguments: ["-f", mountPoint.path], environment: ProcessInfo.processInfo.environment)
            }
        }
        if !Self.isPathMounted(mountPoint) {
            try? FileManager.default.removeItem(at: mountPoint)
        }
        if let dockerPath {
            _ = runProcessSync(executable: dockerPath, arguments: ["rm", "-f", containerName], environment: dockerEnv)
        }
    }

    private struct ProcessResult: Sendable {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    private func runProcess(executable: String, arguments: [String], environment: [String: String]) async throws -> ProcessResult {
        try await Task.detached(priority: .userInitiated) {
            self.runProcessSync(executable: executable, arguments: arguments, environment: environment)
        }.value
    }

    private func runProcessSync(executable: String, arguments: [String], environment: [String: String]) -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return ProcessResult(exitCode: 1, stdout: "", stderr: error.localizedDescription)
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }
}
