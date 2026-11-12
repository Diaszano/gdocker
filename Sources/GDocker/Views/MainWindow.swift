import SwiftUI

enum SidebarItem: Hashable { case containers, images, volumes, networks, permissions, activity }

struct MainWindow: View {
    @Environment(ContainersStore.self) private var store
    @Environment(ImagesStore.self) private var imagesStore
    @Environment(VolumesStore.self) private var volumesStore
    @Environment(NetworksStore.self) private var networksStore
    @Environment(McpController.self) private var mcp
    @State private var section: SidebarItem? = .containers

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            switch section ?? .containers {
            case .containers: containers
            case .images: ImagesView()
            case .volumes: VolumesView()
            case .networks: NetworksView()
            case .permissions: PermissionsView(mcp: mcp)
            case .activity: ActivityView(model: mcp.activityModel)
            }
        }
        .task {
            await imagesStore.refresh()
            await volumesStore.refresh()
            await networksStore.refresh()
        }
        .task(id: section) {
            switch section {
            case .images: await imagesStore.refresh()
            case .volumes: await volumesStore.refresh()
            case .networks: await networksStore.refresh()
            default: break
            }
        }
        .onChange(of: store.connected) { _, connected in
            if connected {
                Task {
                    await imagesStore.refresh()
                    await volumesStore.refresh()
                    await networksStore.refresh()
                }
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
            Section(header: Text("Docker", bundle: .l10n)) {
                HStack {
                    Label {
                        Text("Containers", bundle: .l10n)
                    } icon: {
                        Image(systemName: "shippingbox")
                    }
                    Spacer()
                    Text(verbatim: "\(store.all.count)").foregroundStyle(.secondary)
                }
                .tag(SidebarItem.containers)

                HStack {
                    Label {
                        Text("Images", bundle: .l10n)
                    } icon: {
                        Image(systemName: "square.stack.3d.up")
                    }
                    Spacer()
                    Text(verbatim: "\(imagesStore.count)").foregroundStyle(.secondary)
                }
                .tag(SidebarItem.images)

                HStack {
                    Label {
                        Text("Volumes", bundle: .l10n)
                    } icon: {
                        Image(systemName: "externaldrive")
                    }
                    Spacer()
                    Text(verbatim: "\(volumesStore.count)").foregroundStyle(.secondary)
                }
                .tag(SidebarItem.volumes)

                HStack {
                    Label {
                        Text("Networks", bundle: .l10n)
                    } icon: {
                        Image(systemName: "network")
                    }
                    Spacer()
                    Text(verbatim: "\(networksStore.count)").foregroundStyle(.secondary)
                }
                .tag(SidebarItem.networks)
            }
            Section(header: Text("AI", bundle: .l10n)) {
                McpStatusRow(mcp: mcp)
                Text("Permissions", bundle: .l10n).tag(SidebarItem.permissions)
                Text("AI activity", bundle: .l10n).tag(SidebarItem.activity)
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
