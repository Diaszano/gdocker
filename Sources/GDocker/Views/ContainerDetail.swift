import GDockerCore
import SwiftUI

struct ContainerDetail: View {
    let container: ContainerSummary
    @Binding var selectedTab: Tab
    var onClose: (() -> Void)? = nil

    @Environment(ContainersStore.self) private var store
    @State private var logs = LogsModel()
    @State private var details: ContainerDetails?
    @State private var rawJSON = ""
    @State private var confirmRemove = false
    @State private var terminal = TerminalSession()

    enum Tab: CaseIterable, Hashable {
        case logs, stats, inspect, env, terminal

        var title: LocalizedStringKey {
            switch self {
            case .logs: "Logs"
            case .stats: "Stats"
            case .inspect: "Inspect"
            case .env: "Env"
            case .terminal: "Terminal"
            }
        }

        var systemImage: String {
            switch self {
            case .logs: return "doc.text"
            case .stats: return "waveform.path.ecg"
            case .inspect: return "magnifyingglass"
            case .env: return "curlybraces"
            case .terminal: return "terminal"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            TabStrip(
                selection: $selectedTab,
                items: Tab.allCases.map { .init(tab: $0, title: $0.title, systemImage: $0.systemImage) }
            )
            Divider().overlay(Color.ctp.muted.opacity(0.18))
            content
        }
        .background(Color.ctp.bg)
        // Re-run when the container changes state or an action ran, so the log stream reconnects after a restart.
        .task(id: "\(container.id)|\(container.state)|\(store.revision)") { await load() }
        .onChange(of: logs.showTimestamps) { logs.restart() }
        .onDisappear {
            logs.detach()
            terminal.terminate()
        }
        .confirmationDialog(
            Text("Remove container?", bundle: .l10n), isPresented: $confirmRemove, titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                Task { await store.perform(.remove, on: container.id) }
            } label: { Text("Remove", bundle: .l10n) }
        } message: {
            Text("The container will be deleted permanently.", bundle: .l10n)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                StatusDot(kind: container.statusKind)
                Text(verbatim: container.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.ctp.text)
                    .lineLimit(1)
                Spacer()
                if let onClose {
                    IconActionButton(systemImage: "sidebar.right", tint: Color.ctp.muted, help: "Hide inspector", action: onClose)
                }
            }

            Text(verbatim: subtitle)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.ctp.muted)
                .lineLimit(1)

            HStack(spacing: 8) {
                StatusBadge(kind: container.statusKind, label: statusLabel)
                Text(verbatim: container.status)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.ctp.muted)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 28)
        .padding(.bottom, 10)
    }

    private var statusLabel: LocalizedStringKey {
        switch container.statusKind {
        case .running: "Running"
        case .transitioning: "Restarting"
        case .stopped: "Stopped"
        case .failed: "Failed"
        }
    }

    @ViewBuilder private var content: some View {
        switch selectedTab {
        case .logs: LogsTab(model: logs)
        case .stats: StatsTab(client: store.client, id: container.id)
        case .inspect: InspectTab(rawJSON: rawJSON)
        case .env: EnvTab(env: details?.config.env ?? [])
        case .terminal: TerminalTab(session: terminal, container: container)
        }
    }

    private var subtitle: String {
        // IPv4 and IPv6 bindings of the same port show up twice; list each mapping once.
        let ports = Set(container.ports.compactMap { port in
            port.publicPort.map { ":\($0)→\(port.privatePort)" }
        }).sorted()
        return ([container.image] + ports).joined(separator: " · ")
    }

    private func load() async {
        // A stopped container ends its shell; the next Start opens a fresh one instead of the dead view.
        if TerminalAvailability(state: container.state) != .ready { terminal.terminate() }
        details = nil
        rawJSON = ""
        guard let client = store.client else { return }
        do {
            let result = try await client.inspect(container.id)
            details = result.details
            rawJSON = result.rawJSON
            logs.attach(client: client, id: container.id, tty: result.details.config.tty)
        } catch {
            // The container may have been removed between the list refresh and this call.
        }
    }
}
