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
    }

    func reconnect(containerID: String) {
        terminate()
        start(containerID: containerID)
    }

    func terminate() {
        guard let view else { return }
        view.processDelegate = nil
        view.terminate()
        self.view = nil
    }

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        // SwiftTerm posts process events on the main queue.
        MainActor.assumeIsolated { self.exitCode = exitCode ?? -1 }
    }

    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
}

/// SwiftTerm copies colors once, so dynamic system colors are re-applied when the light/dark appearance changes.
private final class ThemedTerminalView: LocalProcessTerminalView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    private func applyColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            nativeForegroundColor = .textColor
            nativeBackgroundColor = .textBackgroundColor
        }
    }
}
