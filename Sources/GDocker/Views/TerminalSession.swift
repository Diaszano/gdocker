import AppKit
import GDockerCore
import Observation
import SwiftTerm

/// One `docker exec -it` shell for the selected container. Lives in `ContainerDetail` so switching tabs keeps it.
@MainActor @Observable
final class TerminalSession: LocalProcessTerminalViewDelegate {
    private(set) var view: LocalProcessTerminalView?
    private(set) var exitCode: Int32?
    private(set) var isCLIAvailable: Bool
    @ObservationIgnored private var exitWatcher: DispatchSourceProcess?

    init() {
        isCLIAvailable = Self.dockerBinary != nil
    }

    private static var dockerBinary: String? {
        DockerCLI.resolve { FileManager.default.fileExists(atPath: $0) }
    }

    func start(containerID: String) {
        guard view == nil else { return }
        guard let binary = Self.dockerBinary else {
            isCLIAvailable = false
            return
        }
        isCLIAvailable = true
        exitCode = nil
        let terminal = ThemedTerminalView(frame: .zero)
        terminal.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        terminal.processDelegate = self
        var env = DockerCLI.environment(
            base: ProcessInfo.processInfo.environment, socketPath: DockerSocket.discover())
        env["TERM"] = "xterm-256color"
        terminal.startProcess(
            executable: binary,
            args: DockerCLI.terminalArguments(containerID: containerID),
            environment: env.map { "\($0.key)=\($0.value)" })
        view = terminal
        watchExit(of: terminal.process.shellPid)
    }

    /// SwiftTerm 1.11 never reports a shell that exits on its own (and leaves it a zombie), so the app watches it.
    private func watchExit(of pid: pid_t) {
        guard pid > 0 else {
            exitCode = -1  // fork failed
            return
        }
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        source.setEventHandler { [weak self] in
            var status: Int32 = 0
            let reaped = waitpid(pid, &status, WNOHANG) == pid
            MainActor.assumeIsolated {
                self?.exitWatcher?.cancel()
                self?.exitWatcher = nil
                self?.exitCode = reaped ? DockerCLI.exitCode(waitStatus: status) : -1
            }
        }
        exitWatcher = source
        source.activate()
    }

    func reconnect(containerID: String) {
        terminate()
        start(containerID: containerID)
    }

    func terminate() {
        guard let view else { return }
        exitWatcher?.cancel()
        exitWatcher = nil
        view.processDelegate = nil
        let pid = view.process.shellPid
        view.terminate()  // sends SIGTERM
        self.view = nil
        // Reap it so it does not linger as a zombie; docker exits promptly on SIGTERM.
        DispatchQueue.global().async {
            var status: Int32 = 0
            waitpid(pid, &status, 0)
        }
    }

    // Exit is tracked by `watchExit`; SwiftTerm's own callback passes a raw wait status, when it fires at all.
    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {}

    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
}

/// SwiftTerm copies colors once, so the dynamic Catppuccin colors are re-applied when the appearance or theme changes.
private final class ThemedTerminalView: LocalProcessTerminalView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        applyColors()
        NotificationCenter.default.addObserver(
            self, selector: #selector(themeChanged), name: UserDefaults.didChangeNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    @objc private func themeChanged() { applyColors() }

    private func applyColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            nativeForegroundColor = .ctp(\.text)
            nativeBackgroundColor = .ctp(\.bg)
            // SwiftTerm paints the layer only once at init; the strip outside the cell grid shows it.
            layer?.backgroundColor = nativeBackgroundColor.cgColor
        }
    }
}
