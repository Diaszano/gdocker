import SwiftUI

enum SidebarItem: Hashable { case containers, permissions }

struct MainWindow: View {
    @Environment(ContainersStore.self) private var store
    @Environment(McpController.self) private var mcp
    @State private var section: SidebarItem? = .containers

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            switch section ?? .containers {
            case .containers: containers
            case .permissions: PermissionsView(mcp: mcp)
            }
        }
        .alert(
            Text("Docker error", bundle: .l10n),
            isPresented: Binding(get: { store.lastError != nil }, set: { if !$0 { store.lastError = nil } })
        ) {
            Button { } label: { Text("OK", bundle: .l10n) }
        } message: {
            Text(verbatim: store.lastError ?? "")
        }
    }

    private var sidebar: some View {
        List(selection: $section) {
            Section(header: Text(verbatim: "Docker")) {
                HStack {
                    Text("Containers", bundle: .l10n)
                    Spacer()
                    Text(verbatim: "\(store.all.count)").foregroundStyle(.secondary)
                }
                .tag(SidebarItem.containers)
            }
            Section(header: Text("AI", bundle: .l10n)) {
                McpStatusRow(mcp: mcp)
                Text("Permissions", bundle: .l10n).tag(SidebarItem.permissions)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 6) {
                Circle().fill(store.connected ? Color.green : Color.red).frame(width: 8, height: 8)
                store.connected
                    ? Text("Docker connected", bundle: .l10n)
                    : Text("Docker disconnected", bundle: .l10n)
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(10)
        }
        .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
    }

    /// The list and the detail side by side. A plain split view rather than a third navigation column, because the
    /// permissions screen needs the whole width next to the sidebar.
    private var containers: some View {
        HSplitView {
            ContainerList()
                .frame(minWidth: 300, idealWidth: 380, maxWidth: 480)
            Group {
                if let selected = store.selected {
                    ContainerDetail(container: selected).id(selected.id)
                } else {
                    Text("Select a container", bundle: .l10n).foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The MCP server's state in the sidebar: a colored dot, its name, and where it listens or what went wrong.
private struct McpStatusRow: View {
    let mcp: McpController

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text("MCP server", bundle: .l10n)
                Text(verbatim: detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var color: Color {
        switch mcp.state {
        case .running: .green
        case .starting, .stopped: .gray
        case .failed: .red
        }
    }

    private var detail: String {
        switch mcp.state {
        case .running(let port):
            // Strings, not Ints: an Int interpolation is locale-formatted, and pt-BR would show port 7.391.
            String(localized: "localhost:\(String(port)) · clients: \(String(mcp.clientCount))", bundle: .l10n)
        case .starting: String(localized: "Starting…", bundle: .l10n)
        case .stopped: String(localized: "Stopped", bundle: .l10n)
        case .failed(let message): message
        }
    }
}
