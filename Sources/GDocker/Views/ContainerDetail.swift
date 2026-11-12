import GDockerCore
import SwiftUI

struct ContainerDetail: View {
    let container: ContainerSummary
    @Environment(ContainersStore.self) private var store
    @State private var tab = Tab.logs
    @State private var logs = LogsModel()
    @State private var details: ContainerDetails?
    @State private var rawJSON = ""
    @State private var confirmRemove = false

    enum Tab: CaseIterable {
        case logs, stats, inspect, env

        var title: LocalizedStringKey {
            switch self {
            case .logs: "Logs"
            case .stats: "Stats"
            case .inspect: "Inspect"
            case .env: "Env"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Picker(selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.title, bundle: .l10n).tag($0) }
            } label: { EmptyView() }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            Divider()
            content
        }
        // Re-run when the container changes state or an action ran, so the log stream reconnects after a restart.
        .task(id: "\(container.id)|\(container.state)|\(store.revision)") { await load() }
        .onChange(of: logs.showTimestamps) { logs.restart() }
        .onDisappear { logs.detach() }
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
        HStack(alignment: .top, spacing: 10) {
            StatusDot(kind: container.statusKind).padding(.top, 7)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: container.name).font(.title2.bold())
                Text(verbatim: subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { Task { await store.perform(.restart, on: container.id) } } label: {
                Text("Restart", bundle: .l10n)
            }
            if container.isActive {
                Button { Task { await store.perform(.stop, on: container.id) } } label: {
                    Text("Stop", bundle: .l10n)
                }
            } else {
                Button { Task { await store.perform(.start, on: container.id) } } label: {
                    Text("Start", bundle: .l10n)
                }
            }
            Button(role: .destructive) { confirmRemove = true } label: { Text("Remove", bundle: .l10n) }
        }
        .padding(16)
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .logs: LogsTab(model: logs)
        case .stats: StatsTab(client: store.client, id: container.id)
        case .inspect: InspectTab(rawJSON: rawJSON)
        case .env: EnvTab(env: details?.config.env ?? [])
        }
    }

    private var subtitle: String {
        // IPv4 and IPv6 bindings of the same port show up twice; list each mapping once.
        let ports = Set(container.ports.compactMap { port in
            port.publicPort.map { ":\($0)→\(port.privatePort)" }
        }).sorted()
        return ([container.image] + ports + [container.status]).joined(separator: " · ")
    }

    private func load() async {
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
