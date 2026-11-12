import AppKit
import Foundation
import GDockerCore
import GDockerMCP
import Observation

enum ConfigKind { case claudeCodeHTTP, jsonHTTP, claudeDesktopStdio }

/// Owns the MCP server's lifecycle and the pieces the UI watches: permissions, the activity log and the approval queue.
@MainActor @Observable
final class McpController {
    enum State: Equatable {
        case stopped, starting
        case running(port: Int)
        case failed(String)
    }

    private(set) var state = State.stopped
    private(set) var clientCount = 0
    let permissions: PermissionStore
    let activity: ActivityLog
    let approvals: ApprovalQueue

    private let tokenProvider = McpTokenProvider(store: KeychainSecretStore())
    private let router: ToolRouter
    private var server: McpHTTPServer?
    private var poller: Task<Void, Never>?

    init(store: ContainersStore) {
        let directory = Self.supportDirectory
        let permissions = PermissionStore(fileURL: directory.appendingPathComponent("permissions.json"))
        let activity = ActivityLog(fileURL: directory.appendingPathComponent("activity.jsonl"))
        let approvals = ApprovalQueue()
        // GDOCKER_APPROVAL_TIMEOUT (seconds) exists so a verification run does not wait two minutes for a prompt.
        let seconds = ProcessInfo.processInfo.environment["GDOCKER_APPROVAL_TIMEOUT"].flatMap(Double.init) ?? 120
        self.permissions = permissions
        self.activity = activity
        self.approvals = approvals
        router = ToolRouter(
            docker: { await store.client }, permissions: permissions, prompter: approvals, activity: activity,
            approvalTimeout: .seconds(seconds))
        // The `--stdio` bridge reads the endpoint file, so a stale one would point it at a dead port. Only an
        // instance that is serving removes it: a second instance that failed on a busy port must not delete the
        // first one's file when it quits.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                if case .running? = self?.state { McpEndpoint.remove() }
            }
        }
    }

    static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GDocker")
    }

    /// The saved port, or the default when it is missing or outside the allowed range.
    static var configuredPort: Int {
        let saved = UserDefaults.standard.object(forKey: SettingsKey.mcpPort) as? Int ?? SettingsKey.defaultMcpPort
        return SettingsKey.mcpPortRange.contains(saved) ? saved : SettingsKey.defaultMcpPort
    }

    // MARK: - Lifecycle

    func startIfEnabled() async {
        guard UserDefaults.standard.object(forKey: SettingsKey.mcpAutoStart) as? Bool ?? true else { return }
        await start()
    }

    func start() async {
        switch state {
        case .starting, .running: return
        case .stopped, .failed: break
        }
        state = .starting
        let provider = tokenProvider
        // Create the token now: the `--stdio` bridge only reads it, so it must exist before any client connects.
        _ = try? await provider.token()
        let server = McpHTTPServer(
            router: router, token: { try await provider.token() }, requestedPort: Self.configuredPort)
        do {
            let port = try await server.start()
            self.server = server
            if let url = URL(string: "http://127.0.0.1:\(port)/mcp") { try? McpEndpoint.write(url) }
            state = .running(port: port)
            startPolling()
        } catch McpServerError.portInUse(let busy) {
            // A String, not an Int, so the port is not locale-formatted ("7.391" in pt-BR).
            state = .failed(String(localized: "Port \(String(busy)) is already in use", bundle: .l10n))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func stop() async {
        poller?.cancel()
        poller = nil
        await server?.stop()
        server = nil
        McpEndpoint.remove()
        clientCount = 0
        state = .stopped
    }

    func restart() async {
        await stop()
        await start()
    }

    /// Replaces the token; clients still using the old one are rejected at their next request.
    func regenerateToken() async {
        _ = try? await tokenProvider.regenerate()
    }

    // MARK: - Config for clients

    func configSnippet(_ kind: ConfigKind) async -> String {
        let token = (try? await tokenProvider.token()) ?? ""
        let port: Int
        if case .running(let running) = state { port = running } else { port = Self.configuredPort }
        let url = URL(string: "http://127.0.0.1:\(port)/mcp")!
        switch kind {
        case .claudeCodeHTTP: return McpConfigSnippets.claudeCode(url: url, token: token)
        case .jsonHTTP: return McpConfigSnippets.jsonHTTP(url: url, token: token)
        case .claudeDesktopStdio:
            return McpConfigSnippets.claudeDesktopStdio(
                executable: Bundle.main.executablePath ?? "/Applications/GDocker.app/Contents/MacOS/GDocker")
        }
    }

    // MARK: - Status

    private func startPolling() {
        poller?.cancel()
        poller = Task { [weak self] in
            while !Task.isCancelled {
                if let server = self?.server {
                    let count = await server.clientCount()
                    self?.clientCount = count
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}
