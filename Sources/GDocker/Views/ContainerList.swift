import GDockerCore
import SwiftUI

struct ContainerList: View {
    @Environment(ContainersStore.self) private var store
    @Binding var showInspector: Bool
    var onOpenTab: (String, ContainerDetail.Tab) -> Void

    @State private var confirmRemoveID: String?
    @State private var confirmBulkRemove = false
    @State private var confirmPruneStopped = false

    @State private var nameMinWidth: CGFloat = 200
    @State private var stateWidth: CGFloat = 118
    @State private var portsWidth: CGFloat = 96
    @State private var sizeWidth: CGFloat = 68
    private let actionsWidth: CGFloat = 130

    private var visibleContainerIDs: [String] {
        store.visibleGroups.flatMap(\.containers).map(\.id)
    }

    private var selectAllState: TableCheckState {
        let visible = visibleContainerIDs
        guard !visible.isEmpty else { return .unchecked }
        let selectedVisible = visible.filter { store.selectedIDs.contains($0) }.count
        if selectedVisible == 0 { return .unchecked }
        return selectedVisible == visible.count ? .checked : .indeterminate
    }

    private var minTableWidth: CGFloat {
        // checkbox(22) + logo(28) + columns + dividers(4*10) + gaps + horizontal padding(40)
        40 + 22 + 28 + nameMinWidth + stateWidth + portsWidth + sizeWidth + actionsWidth + 96
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                header
                GeometryReader { geo in
                    ScrollView(.horizontal) {
                        VStack(spacing: 0) {
                            tableHeader
                            Divider().overlay(Color.ctp.muted.opacity(0.18))
                            ScrollView(.vertical) {
                                LazyVStack(spacing: 0) {
                                    ForEach(store.visibleGroups) { group in
                                        GroupHeader(group: group)
                                        ForEach(group.containers) { container in
                                            ContainerRow(
                                                container: container,
                                                isSelected: store.selectedID == container.id,
                                                isChecked: store.selectedIDs.contains(container.id),
                                                nameMinWidth: nameMinWidth,
                                                stateWidth: stateWidth,
                                                portsWidth: portsWidth,
                                                sizeWidth: sizeWidth,
                                                actionsWidth: actionsWidth,
                                                onSelect: { store.selectedID = container.id },
                                                onToggleCheck: { toggleCheck(container.id) },
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
                                .padding(.bottom, store.selectedIDs.isEmpty ? 0 : 72)
                            }
                        }
                        .frame(minWidth: max(geo.size.width, minTableWidth), maxHeight: .infinity, alignment: .topLeading)
                    }
                }
            }
            .background(Color.ctp.bg)

            if !store.selectedIDs.isEmpty {
                BulkActionBar(selectedCount: store.selectedIDs.count, onClear: { store.selectedIDs.removeAll() }) {
                    BulkPillButton(title: "Start", systemImage: "play.fill", tint: Color.ctp.ok) {
                        let ids = store.selectedIDs
                        Task { await store.performBulk(.start, on: ids) }
                    }
                    BulkPillButton(title: "Stop", systemImage: "stop.fill", tint: Color.ctp.text) {
                        let ids = store.selectedIDs
                        Task { await store.performBulk(.stop, on: ids) }
                    }
                    BulkPillButton(title: "Restart", systemImage: "arrow.clockwise", tint: Color.ctp.accent) {
                        let ids = store.selectedIDs
                        Task { await store.performBulk(.restart, on: ids) }
                    }
                    BulkPillButton(title: "Remove", systemImage: "trash", tint: Color.ctp.err) {
                        confirmBulkRemove = true
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.16), value: store.selectedIDs.isEmpty)
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
        .confirmationDialog(
            Text("Remove selected containers?", bundle: .l10n),
            isPresented: $confirmBulkRemove,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                let ids = store.selectedIDs
                Task { await store.performBulk(.remove, on: ids) }
            } label: { Text("Remove", bundle: .l10n) }
        } message: {
            Text(verbatim: String(localized: "\(String(store.selectedIDs.count)) selected containers will be removed permanently.", bundle: .l10n))
        }
        .confirmationDialog(
            Text("Prune stopped containers?", bundle: .l10n),
            isPresented: $confirmPruneStopped,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                Task { await store.pruneStopped() }
            } label: { Text("Prune", bundle: .l10n) }
        } message: {
            Text("All stopped containers will be removed permanently.", bundle: .l10n)
        }
    }

    private func toggleCheck(_ id: String) {
        if store.selectedIDs.contains(id) {
            store.selectedIDs.remove(id)
        } else {
            store.selectedIDs.insert(id)
        }
    }

    private func toggleSelectAll() {
        let visible = visibleContainerIDs
        if selectAllState == .checked {
            store.selectedIDs.subtract(visible)
        } else {
            store.selectedIDs.formUnion(visible)
        }
    }

    private var header: some View {
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("Containers", bundle: .l10n)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.ctp.text)
                Spacer()

                TableSearchField(text: $store.searchText, prompt: String(localized: "Search containers", bundle: .l10n), width: 260)

                IconActionButton(
                    systemImage: "arrow.clockwise",
                    help: LocalizedStringKey(String(localized: "Refresh", bundle: .l10n))
                ) {
                    Task { await store.refresh() }
                }

                IconActionButton(
                    systemImage: "trash.slash",
                    tint: Color.ctp.err,
                    help: LocalizedStringKey(String(localized: "Prune stopped containers", bundle: .l10n))
                ) {
                    confirmPruneStopped = true
                }

                SectionMenuButton(help: LocalizedStringKey(String(localized: "Section actions", bundle: .l10n))) {
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        Label { Text("Refresh", bundle: .l10n) } icon: { Image(systemName: "arrow.clockwise") }
                    }
                    Button(role: .destructive) {
                        confirmPruneStopped = true
                    } label: {
                        Label { Text("Prune stopped containers", bundle: .l10n) } icon: { Image(systemName: "trash.slash") }
                    }
                    if !store.selectedIDs.isEmpty {
                        Divider()
                        Button {
                            store.selectedIDs.removeAll()
                        } label: {
                            Label { Text("Clear", bundle: .l10n) } icon: { Image(systemName: "xmark.circle") }
                        }
                    }
                }

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
                FilterPill(title: LocalizedStringKey(String(localized: "All", bundle: .l10n)), dotColor: nil, isSelected: store.statusFilter == .all) {
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
        .padding(.top, 28)
        .padding(.bottom, 12)
    }

    private var tableHeader: some View {
        HStack(spacing: 6) {
            TableCheckbox(
                state: selectAllState,
                help: LocalizedStringKey(String(localized: "Select all", bundle: .l10n)),
                action: toggleSelectAll
            )
            Spacer().frame(width: 28) // logo(28) alignment

            Text("Name", bundle: .l10n)
                .frame(minWidth: nameMinWidth, maxWidth: .infinity, alignment: .leading)
            ColumnResizeDivider(width: $nameMinWidth, minWidth: 180)

            Text("State", bundle: .l10n)
                .frame(width: stateWidth, alignment: .leading)
            ColumnResizeDivider(width: $stateWidth, minWidth: 100)

            Text("Ports", bundle: .l10n)
                .frame(width: portsWidth, alignment: .leading)
            ColumnResizeDivider(width: $portsWidth, minWidth: 76)

            Text("Size", bundle: .l10n)
                .frame(width: sizeWidth, alignment: .leading)
            ColumnResizeDivider(width: $sizeWidth, minWidth: 64)

            Text("Actions", bundle: .l10n)
                .frame(width: actionsWidth, alignment: .leading)
        }
        .textCase(.uppercase)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Color.ctp.muted)
        .padding(.horizontal, 20)
        .padding(.vertical, 7)
        .background(Color.ctp.side.opacity(0.65))
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
    let nameMinWidth: CGFloat
    let stateWidth: CGFloat
    let portsWidth: CGFloat
    let sizeWidth: CGFloat
    let actionsWidth: CGFloat
    let onSelect: () -> Void
    let onToggleCheck: () -> Void
    let onAction: (ContainerAction) -> Void
    let onOpenTab: (ContainerDetail.Tab) -> Void

    @State private var hovered = false

    var body: some View {
        HStack(spacing: 6) {
            TableCheckbox(state: isChecked ? .checked : .unchecked, action: onToggleCheck)

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
            .frame(minWidth: nameMinWidth, maxWidth: .infinity, alignment: .leading)

            Spacer().frame(width: 10)

            StatusBadge(kind: container.statusKind, label: statusLabel)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: stateWidth, alignment: .leading)

            Spacer().frame(width: 10)

            Text(verbatim: formattedPorts)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.ctp.muted)
                .lineLimit(1)
                .frame(width: portsWidth, alignment: .leading)

            Spacer().frame(width: 10)

            Text(verbatim: formattedSize)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.ctp.muted)
                .lineLimit(1)
                .frame(width: sizeWidth, alignment: .leading)

            Spacer().frame(width: 10)

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
                SectionMenuButton {
                    Button { onOpenTab(.logs) } label: { Label { Text("Logs", bundle: .l10n) } icon: { Image(systemName: "doc.text") } }
                    Button { onOpenTab(.stats) } label: { Label { Text("Stats", bundle: .l10n) } icon: { Image(systemName: "waveform.path.ecg") } }
                    Button { onOpenTab(.inspect) } label: { Label { Text("Inspect", bundle: .l10n) } icon: { Image(systemName: "magnifyingglass") } }
                    Button { onOpenTab(.env) } label: { Label { Text("Env", bundle: .l10n) } icon: { Image(systemName: "curlybraces") } }
                    Button { onOpenTab(.terminal) } label: { Label { Text("Terminal", bundle: .l10n) } icon: { Image(systemName: "terminal") } }
                }
            }
            .frame(width: actionsWidth, alignment: .leading)
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
