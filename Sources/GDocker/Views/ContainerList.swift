import GDockerCore
import SwiftUI

struct ContainerList: View {
    @Environment(ContainersStore.self) private var store
    @Binding var showInspector: Bool
    var onOpenTab: (String, ContainerDetail.Tab) -> Void

    @State private var confirmRemoveID: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            tableHeader
            Divider().overlay(Color.ctp.muted.opacity(0.18))
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.visibleGroups) { group in
                        GroupHeader(group: group)
                        ForEach(group.containers) { container in
                            ContainerRow(
                                container: container,
                                isSelected: store.selectedID == container.id,
                                isChecked: store.selectedIDs.contains(container.id),
                                onSelect: { store.selectedID = container.id },
                                onToggleCheck: {
                                    if store.selectedIDs.contains(container.id) {
                                        store.selectedIDs.remove(container.id)
                                    } else {
                                        store.selectedIDs.insert(container.id)
                                    }
                                },
                                onAction: { action in
                                    if action == .remove {
                                        confirmRemoveID = container.id
                                    } else {
                                        Task { await store.perform(action, on: container.id) }
                                    }
                                },
                                onOpenTab: { tab in
                                    onOpenTab(container.id, tab)
                                }
                            )
                            Divider().overlay(Color.ctp.muted.opacity(0.1))
                        }
                    }
                }
            }
        }
        .background(Color.ctp.bg)
        .confirmationDialog(
            Text("Remove container?", bundle: .l10n),
            isPresented: Binding(get: { confirmRemoveID != nil }, set: { if !$0 { confirmRemoveID = nil } }),
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                if let id = confirmRemoveID {
                    confirmRemoveID = nil
                    Task { await store.perform(.remove, on: id) }
                }
            } label: { Text("Remove", bundle: .l10n) }
        } message: {
            Text("The container will be deleted permanently.", bundle: .l10n)
        }
    }

    private var header: some View {
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("Containers", bundle: .l10n)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.ctp.text)
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.ctp.muted)
                    TextField(text: $store.searchText, prompt: Text("Search containers", bundle: .l10n)) {
                        EmptyView()
                    }
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .frame(width: 190)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.ctp.side)
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.ctp.muted.opacity(0.24), lineWidth: 1))
                )

                IconActionButton(
                    systemImage: showInspector ? "sidebar.right" : "sidebar.trailing",
                    tint: showInspector ? Color.ctp.accent : Color.ctp.muted,
                    help: showInspector
                        ? LocalizedStringKey(String(localized: "Hide inspector", bundle: .l10n))
                        : LocalizedStringKey(String(localized: "Show inspector", bundle: .l10n))
                ) {
                    withAnimation(.easeInOut(duration: 0.16)) { showInspector.toggle() }
                }
            }

            HStack(spacing: 8) {
                FilterPill(title: "All", dotColor: nil, isSelected: store.statusFilter == .all) {
                    store.statusFilter = .all
                }
                FilterPill(title: "Running", dotColor: Color.ctp.ok, isSelected: store.statusFilter == .running) {
                    store.statusFilter = .running
                }
                FilterPill(title: "Stopped", dotColor: Color.ctp.muted, isSelected: store.statusFilter == .stopped) {
                    store.statusFilter = .stopped
                }
                FilterPill(title: "Failed", dotColor: Color.ctp.err, isSelected: store.statusFilter == .failed) {
                    store.statusFilter = .failed
                }
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var tableHeader: some View {
        HStack(spacing: 12) {
            Spacer().frame(width: 56) // checkbox + logo
            Text("Name", bundle: .l10n).frame(maxWidth: .infinity, alignment: .leading)
            Text("State", bundle: .l10n).frame(width: 112, alignment: .leading)
            Text("Ports", bundle: .l10n).frame(width: 96, alignment: .leading)
            Text("Size", bundle: .l10n).frame(width: 72, alignment: .leading)
            Text("Actions", bundle: .l10n).frame(width: 132, alignment: .leading)
        }
        .textCase(.uppercase)
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(Color.ctp.muted)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color.ctp.side.opacity(0.6))
    }
}

private struct GroupHeader: View {
    let group: ContainerGroup

    private var runningCount: Int {
        group.containers.filter { $0.statusKind == .running }.count
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.stack.3d.forward.dottedline")
                .font(.system(size: 11))
                .foregroundStyle(Color.ctp.muted)
            if let project = group.project {
                Text(verbatim: project)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.ctp.text)
                Text(verbatim: String(localized: "Compose · \(String(runningCount)) of \(String(group.containers.count)) running", bundle: .l10n))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.ctp.muted)
            } else {
                Text("No group", bundle: .l10n)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.ctp.muted)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 7)
        .background(Color.ctp.side.opacity(0.45))
    }
}

private struct ContainerRow: View {
    let container: ContainerSummary
    let isSelected: Bool
    let isChecked: Bool
    let onSelect: () -> Void
    let onToggleCheck: () -> Void
    let onAction: (ContainerAction) -> Void
    let onOpenTab: (ContainerDetail.Tab) -> Void

    @State private var hovered = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggleCheck) {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isChecked ? Color.ctp.accent : Color.ctp.muted.opacity(0.45), lineWidth: 1.2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(isChecked ? Color.ctp.accent : Color.clear))
                    .overlay {
                        if isChecked {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.ctp.bg)
                        }
                    }
                    .frame(width: 15, height: 15)
            }
            .buttonStyle(.plain)

            ServiceLogo(image: container.image, size: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: container.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.ctp.text)
                    .lineLimit(1)
                Text(verbatim: container.image)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.ctp.muted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            StatusBadge(kind: container.statusKind, label: statusLabel)
                .frame(width: 112, alignment: .leading)

            Text(verbatim: formattedPorts)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.ctp.muted)
                .lineLimit(1)
                .frame(width: 96, alignment: .leading)

            Text(verbatim: formattedSize)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.ctp.muted)
                .lineLimit(1)
                .frame(width: 72, alignment: .leading)

            HStack(spacing: 6) {
                IconActionButton(systemImage: "arrow.clockwise", help: "Restart") {
                    onAction(.restart)
                }
                IconActionButton(
                    systemImage: container.isActive ? "stop.fill" : "play.fill",
                    help: container.isActive ? "Stop" : "Start"
                ) {
                    onAction(container.isActive ? .stop : .start)
                }
                IconActionButton(systemImage: "trash", tint: Color.ctp.err, help: "Remove") {
                    onAction(.remove)
                }
                Menu {
                    Button { onOpenTab(.logs) } label: { Label { Text("Logs", bundle: .l10n) } icon: { Image(systemName: "doc.text") } }
                    Button { onOpenTab(.stats) } label: { Label { Text("Stats", bundle: .l10n) } icon: { Image(systemName: "waveform.path.ecg") } }
                    Button { onOpenTab(.inspect) } label: { Label { Text("Inspect", bundle: .l10n) } icon: { Image(systemName: "magnifyingglass") } }
                    Button { onOpenTab(.env) } label: { Label { Text("Env", bundle: .l10n) } icon: { Image(systemName: "curlybraces") } }
                    Button { onOpenTab(.terminal) } label: { Label { Text("Terminal", bundle: .l10n) } icon: { Image(systemName: "terminal") } }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.ctp.text)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.ctp.muted.opacity(0.28), lineWidth: 1)
                        )
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 28, height: 28)
            }
            .frame(width: 132, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(isSelected ? Color.ctp.hover : (hovered ? Color.ctp.hover.opacity(0.45) : Color.clear))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture(perform: onSelect)
    }

    private var statusLabel: LocalizedStringKey {
        switch container.statusKind {
        case .running: "Running"
        case .transitioning: "Restarting"
        case .stopped: "Stopped"
        case .failed: "Failed"
        }
    }

    private var formattedPorts: String {
        let mappings = Set(container.ports.compactMap { port in
            port.publicPort.map { "\($0)→\(port.privatePort)" }
        }).sorted()
        return mappings.isEmpty ? "—" : mappings.joined(separator: ", ")
    }

    private var formattedSize: String {
        guard let bytes = container.sizeRw else { return "—" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
