import GDockerCore
import SwiftUI

enum SidebarItem: Hashable { case containers, images, volumes, networks, compose, permissions, activity }

struct MainWindow: View {
    @Environment(ContainersStore.self) private var store
    @Environment(ImagesStore.self) private var imagesStore
    @Environment(VolumesStore.self) private var volumesStore
    @Environment(NetworksStore.self) private var networksStore
    @Environment(ComposeStore.self) private var composeStore
    @Environment(McpController.self) private var mcp
    @State private var section: SidebarItem = .containers
    @State private var sidebarCollapsed = false
    @State private var showInspector = false
    @State private var inspectorTab = ContainerDetail.Tab.logs
    // Dynamic colors don't invalidate SwiftUI when only the flavor changes, so the theme keys the view tree.
    @AppStorage(SettingsKey.theme) private var theme = Theme.system

    private var runningCount: Int {
        store.all.filter { $0.statusKind == .running }.count
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle()
                .fill(Color.ctp.muted.opacity(0.18))
                .frame(width: 1)

            VStack(spacing: 0) {
                detailContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                StatusBar(
                    connected: store.connected,
                    runningCount: runningCount,
                    totalCount: store.all.count,
                    hostInfo: store.hostInfo,
                    mcp: mcp
                )
            }
            .background(Color.ctp.bg)
        }
        .background(Color.ctp.bg)
        .tint(Color.ctp.accent)
        .id(theme)
        .task {
            await imagesStore.refresh()
            await volumesStore.refresh()
            await networksStore.refresh()
            await composeStore.refresh()
        }
        .task(id: section) {
            switch section {
            case .images: await imagesStore.refresh()
            case .volumes: await volumesStore.refresh()
            case .networks: await networksStore.refresh()
            case .compose: await composeStore.refresh()
            default: break
            }
        }
        .onChange(of: store.connected) { _, connected in
            if connected {
                Task {
                    await imagesStore.refresh()
                    await volumesStore.refresh()
                    await networksStore.refresh()
                    await composeStore.refresh()
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

    @ViewBuilder private var detailContent: some View {
        switch section {
        case .containers: containers
        case .images: ImagesView()
        case .volumes: VolumesView()
        case .networks: NetworksView()
        case .compose: ComposeView()
        case .permissions: PermissionsView(mcp: mcp)
        case .activity: ActivityView(model: mcp.activityModel, approvalModel: mcp.approvalModel)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarHeader
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if !sidebarCollapsed {
                        sectionHeader("DOCKER")
                    }
                    navButton(.containers, title: "Containers", icon: "shippingbox", count: store.all.count)
                    navButton(.images, title: "Images", icon: "square.stack.3d.up", count: imagesStore.count)
                    navButton(.volumes, title: "Volumes", icon: "externaldrive", count: volumesStore.count)
                    navButton(.networks, title: "Networks", icon: "network", count: networksStore.count)
                    navButton(.compose, title: "Compose", icon: "square.stack.3d.forward.dottedline", count: composeStore.activeCount)

                    if !sidebarCollapsed {
                        sectionHeader("AI")
                            .padding(.top, 10)
                    } else {
                        Divider().padding(.vertical, 8).padding(.horizontal, 10)
                    }

                    if !sidebarCollapsed {
                        McpStatusRow(mcp: mcp)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                    }
                    navButton(.activity, title: "AI activity", icon: "waveform.path.ecg", indented: true)
                    navButton(.permissions, title: "Permissions", icon: "checkmark.shield", indented: true)
                }
                .padding(.horizontal, sidebarCollapsed ? 8 : 10)
                .padding(.top, 8)
            }
            Spacer(minLength: 8)
            RuntimeCard(
                connected: store.connected,
                runningCount: runningCount,
                totalCount: store.all.count,
                hostInfo: store.hostInfo,
                compact: sidebarCollapsed
            )
        }
        .frame(width: sidebarCollapsed ? 60 : 220)
        .background(Color.ctp.side)
    }

    private var sidebarHeader: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.ctp.accent)
                .frame(width: 24, height: 24)
                .overlay {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.ctp.bg)
                }
            if !sidebarCollapsed {
                Text(verbatim: "GDocker")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.ctp.text)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) { sidebarCollapsed = true }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.ctp.muted)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: sidebarCollapsed ? .center : .leading)
        .padding(.horizontal, sidebarCollapsed ? 0 : 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            if sidebarCollapsed {
                withAnimation(.easeInOut(duration: 0.16)) { sidebarCollapsed = false }
            }
        }
    }

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title, bundle: .l10n)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.ctp.muted)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
    }

    private func navButton(
        _ item: SidebarItem,
        title: LocalizedStringKey,
        icon: String,
        count: Int? = nil,
        indented: Bool = false
    ) -> some View {
        let active = section == item
        return Button {
            section = item
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: active ? .semibold : .regular))
                    .foregroundStyle(active ? Color.ctp.accent : Color.ctp.muted)
                    .frame(width: 18)
                if !sidebarCollapsed {
                    Text(title, bundle: .l10n)
                        .font(.system(size: 13, weight: active ? .semibold : .regular))
                        .foregroundStyle(active ? Color.ctp.text : Color.ctp.muted)
                    Spacer()
                    if let count {
                        Text(verbatim: "\(count)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color.ctp.muted)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: sidebarCollapsed ? .center : .leading)
            .padding(.leading, indented && !sidebarCollapsed ? 26 : (sidebarCollapsed ? 0 : 10))
            .padding(.trailing, sidebarCollapsed ? 0 : 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(active ? Color.ctp.hover : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(sidebarCollapsed ? Text(title, bundle: .l10n) : Text(verbatim: ""))
    }

    private var containers: some View {
        HSplitView {
            ContainerList(
                showInspector: $showInspector,
                onOpenTab: { containerID, tab in
                    store.selectedID = containerID
                    inspectorTab = tab
                    showInspector = true
                }
            )
            .frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)

            if showInspector {
                Group {
                    if let selected = store.selected {
                        ContainerDetail(
                            container: selected,
                            selectedTab: $inspectorTab,
                            onClose: { showInspector = false }
                        )
                        .id(selected.id)
                    } else {
                        Text("Select a container", bundle: .l10n)
                            .foregroundStyle(Color.ctp.muted)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(minWidth: 380, idealWidth: 420, maxWidth: 520, maxHeight: .infinity)
            }
        }
    }
}

/// The MCP server's state in the sidebar: icon, title, and a subtle status dot.
private struct McpStatusRow: View {
    let mcp: McpController

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "server.rack")
                .font(.system(size: 13))
                .foregroundStyle(Color.ctp.text)
                .frame(width: 18)
            Text("MCP server", bundle: .l10n)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.ctp.text)
            Spacer()
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
        }
        .help(detail)
    }

    private var color: Color {
        switch mcp.state {
        case .running: Color.ctp.ok
        case .starting, .stopped: Color.ctp.muted
        case .failed: Color.ctp.err
        }
    }

    private var detail: String {
        switch mcp.state {
        case .running(let port):
            String(localized: "localhost:\(String(port)) · clients: \(String(mcp.clientCount))", bundle: .l10n)
        case .starting: String(localized: "Starting…", bundle: .l10n)
        case .stopped: String(localized: "Stopped", bundle: .l10n)
        case .failed(let message): message
        }
    }
}
