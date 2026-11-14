import GDockerCore
import SwiftTerm
import SwiftUI

struct TerminalTab: View {
    let session: TerminalSession
    let container: ContainerSummary
    @Environment(ContainersStore.self) private var store

    var body: some View {
        Group {
            if !session.isCLIAvailable {
                unavailable(
                    Text("Docker CLI not found", bundle: .l10n), icon: "terminal",
                    description: Text("The terminal needs the Docker command-line tool installed.", bundle: .l10n)
                ) { EmptyView() }
            } else {
                switch TerminalAvailability(state: container.state) {
                case .stopped:
                    unavailable(Text("Container is not running", bundle: .l10n), icon: "stop.circle") {
                        Button { Task { await store.perform(.start, on: container.id) } } label: {
                            Text("Start", bundle: .l10n)
                        }
                    }
                case .paused:
                    unavailable(Text("Container is paused", bundle: .l10n), icon: "pause.circle") { EmptyView() }
                case .restarting:
                    unavailable(Text("Container is restarting", bundle: .l10n), icon: "arrow.clockwise.circle") { EmptyView() }
                case .ready:
                    shell
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var shell: some View {
        VStack(spacing: 0) {
            if let view = session.view {
                TerminalHost(view: view).id(ObjectIdentifier(view))
            }
            if let code = session.exitCode {
                Divider()
                HStack {
                    Text(verbatim: String(localized: "Session ended (code \(String(code)))", bundle: .l10n)).foregroundStyle(Color.ctp.muted)
                    Spacer()
                    Button { session.reconnect(containerID: container.id) } label: {
                        Text("Reconnect", bundle: .l10n)
                    }
                }
                .padding(8)
            }
        }
        .task(id: container.state) { session.start(containerID: container.id) }
    }

    private func unavailable(
        _ title: Text, icon: String, description: Text? = nil,
        @ViewBuilder actions: () -> some View
    ) -> some View {
        ContentUnavailableView {
            Label {
                title
            } icon: {
                Image(systemName: icon)
            }
        } description: {
            if let description { description }
        } actions: {
            actions()
        }
    }
}

private struct TerminalHost: NSViewRepresentable {
    let view: LocalProcessTerminalView

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}
}
