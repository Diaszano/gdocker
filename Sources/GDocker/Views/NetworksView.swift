import Foundation
import GDockerCore
import SwiftUI

struct NetworksView: View {
    @Environment(NetworksStore.self) private var store
    @Environment(ContainersStore.self) private var containersStore
    @State private var confirmRemoveTarget: NetworkSummary?
    @State private var confirmBulkRemove = false
    @State private var confirmPrune = false

    @State private var nameMinWidth: CGFloat = 200
    @State private var driverWidth: CGFloat = 84
    @State private var scopeWidth: CGFloat = 76
    @State private var containersWidth: CGFloat = 88
    @State private var idWidth: CGFloat = 110
    private let actionsWidth: CGFloat = 64

    private var selectableVisibleIDs: [String] {
        store.filteredNetworks.filter { !$0.isDefaultNetwork }.map(\.id)
    }

    private var selectAllState: TableCheckState {
        let visible = selectableVisibleIDs
        guard !visible.isEmpty else { return .unchecked }
        let checked = visible.filter { store.selectedIDs.contains($0) }.count
        if checked == 0 { return .unchecked }
        return checked == visible.count ? .checked : .indeterminate
    }

    private var minTableWidth: CGFloat {
        40 + 22 + 28 + nameMinWidth + driverWidth + scopeWidth + containersWidth + idWidth + actionsWidth + 112
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                header
                content
            }
            .background(Color.ctp.bg)

            if !store.selectedIDs.isEmpty {
                BulkActionBar(selectedCount: store.selectedIDs.count, onClear: { store.selectedIDs.removeAll() }) {
                    BulkPillButton(title: "Remove", systemImage: "trash", tint: Color.ctp.err) {
                        confirmBulkRemove = true
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.16), value: store.selectedIDs.isEmpty)
        .task { await store.refresh() }
        .confirmationDialog(
            Text("Remove network?", bundle: .l10n),
            isPresented: Binding(get: { confirmRemoveTarget != nil }, set: { if !$0 { confirmRemoveTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                if let target = confirmRemoveTarget, !target.isDefaultNetwork {
                    confirmRemoveTarget = nil
                    Task { await store.remove(id: target.id) }
                }
            } label: { Text("Remove", bundle: .l10n) }
        } message: {
            if let target = confirmRemoveTarget {
                Text(verbatim: String(localized: "The network '\(target.name)' will be removed permanently.", bundle: .l10n))
            } else {
                Text("The selected network will be removed permanently.", bundle: .l10n)
            }
        }
        .confirmationDialog(
            Text("Remove selected networks?", bundle: .l10n),
            isPresented: $confirmBulkRemove,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                let ids = store.selectedIDs
                Task { await store.remove(ids: ids) }
            } label: { Text("Remove", bundle: .l10n) }
        } message: {
            Text(verbatim: String(localized: "\(String(store.selectedIDs.count)) selected networks will be removed permanently.", bundle: .l10n))
        }
        .confirmationDialog(
            Text("Prune unused networks?", bundle: .l10n),
            isPresented: $confirmPrune,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                Task { await store.prune() }
            } label: { Text("Prune Networks", bundle: .l10n) }
        } message: {
            Text("All networks not used by at least one container will be removed permanently. Default networks will not be removed.", bundle: .l10n)
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

    private var header: some View {
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Networks", bundle: .l10n)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.ctp.text)
                    Text(verbatim: subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.ctp.muted)
                }
                Spacer()

                TableSearchField(text: $store.searchText, prompt: String(localized: "Search networks", bundle: .l10n), width: 260)

                IconActionButton(
                    systemImage: "arrow.clockwise",
                    help: LocalizedStringKey(String(localized: "Refresh networks", bundle: .l10n))
                ) {
                    Task { await store.refresh() }
                }

                IconActionButton(
                    systemImage: "trash.slash",
                    tint: Color.ctp.err,
                    help: LocalizedStringKey(String(localized: "Prune Networks", bundle: .l10n))
                ) {
                    confirmPrune = true
                }

                SectionMenuButton(help: LocalizedStringKey(String(localized: "Section actions", bundle: .l10n))) {
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        Label { Text("Refresh", bundle: .l10n) } icon: { Image(systemName: "arrow.clockwise") }
                    }
                    Button(role: .destructive) {
                        confirmPrune = true
                    } label: {
                        Label { Text("Prune Networks", bundle: .l10n) } icon: { Image(systemName: "trash.slash") }
                    }
                }
            }

            HStack(spacing: 8) {
                FilterPill(title: LocalizedStringKey(String(localized: "All", bundle: .l10n)), dotColor: nil, isSelected: store.filter == .all) {
                    store.filter = .all
                }
                FilterPill(title: LocalizedStringKey(String(localized: "Custom", bundle: .l10n)), dotColor: Color.ctp.accent, isSelected: store.filter == .custom) {
                    store.filter = .custom
                }
                FilterPill(title: LocalizedStringKey(String(localized: "System", bundle: .l10n)), dotColor: Color.ctp.muted, isSelected: store.filter == .system) {
                    store.filter = .system
                }
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var content: some View {
        let items = store.filteredNetworks
        if !containersStore.connected || store.all.isEmpty || items.isEmpty {
            ResourceEmptyState(
                connected: containersStore.connected,
                isAllEmpty: store.all.isEmpty,
                searchText: store.searchText,
                emptyTitle: String(localized: "No Networks", bundle: .l10n),
                emptySystemImage: "network",
                emptyDescription: String(localized: "No Docker networks found.", bundle: .l10n)
            )
        } else {
            GeometryReader { geo in
                ScrollView(.horizontal) {
                    VStack(spacing: 0) {
                        tableHeader
                        Divider().overlay(Color.ctp.muted.opacity(0.18))
                        ScrollView(.vertical) {
                            LazyVStack(spacing: 0) {
                                ForEach(items) { network in
                                    NetworkRow(
                                        network: network,
                                        isSelected: store.selectedID == network.id,
                                        isChecked: store.selectedIDs.contains(network.id),
                                        nameMinWidth: nameMinWidth,
                                        driverWidth: driverWidth,
                                        scopeWidth: scopeWidth,
                                        containersWidth: containersWidth,
                                        idWidth: idWidth,
                                        actionsWidth: actionsWidth,
                                        onSelect: { store.selectedID = network.id },
                                        onToggleCheck: { toggleCheck(network) },
                                        onRemove: { confirmRemoveTarget = network }
                                    )
                                    Divider().overlay(Color.ctp.muted.opacity(0.1))
                                }
                            }
                            .padding(.bottom, store.selectedIDs.isEmpty ? 0 : 72)
                        }
                    }
                    .frame(minWidth: max(geo.size.width, minTableWidth), maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
    }

    private var tableHeader: some View {
        HStack(spacing: 6) {
            TableCheckbox(
                state: selectAllState,
                help: LocalizedStringKey(String(localized: "Select all", bundle: .l10n)),
                action: toggleSelectAll
            )
            Spacer().frame(width: 28)

            Text("Name", bundle: .l10n)
                .frame(minWidth: nameMinWidth, maxWidth: .infinity, alignment: .leading)
            ColumnResizeDivider(width: $nameMinWidth, minWidth: 180)

            Text("Driver", bundle: .l10n)
                .frame(width: driverWidth, alignment: .leading)
            ColumnResizeDivider(width: $driverWidth, minWidth: 70)

            Text("Scope", bundle: .l10n)
                .frame(width: scopeWidth, alignment: .leading)
            ColumnResizeDivider(width: $scopeWidth, minWidth: 70)

            Text("Containers", bundle: .l10n)
                .frame(width: containersWidth, alignment: .leading)
            ColumnResizeDivider(width: $containersWidth, minWidth: 76)

            Text("Network ID", bundle: .l10n)
                .frame(width: idWidth, alignment: .leading)
            ColumnResizeDivider(width: $idWidth, minWidth: 96)

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

    private func toggleCheck(_ network: NetworkSummary) {
        guard !network.isDefaultNetwork else { return }
        if store.selectedIDs.contains(network.id) {
            store.selectedIDs.remove(network.id)
        } else {
            store.selectedIDs.insert(network.id)
        }
    }

    private func toggleSelectAll() {
        let visible = selectableVisibleIDs
        if selectAllState == .checked {
            store.selectedIDs.subtract(visible)
        } else {
            store.selectedIDs.formUnion(visible)
        }
    }

    private var subtitle: String {
        if store.searchText.isEmpty && store.filter == .all {
            if store.count == 1 {
                return String(localized: "\(String(store.count)) network", bundle: .l10n)
            } else {
                return String(localized: "\(String(store.count)) networks", bundle: .l10n)
            }
        } else {
            return String(localized: "\(String(store.filteredNetworks.count)) of \(String(store.count))", bundle: .l10n)
        }
    }
}

private struct NetworkRow: View {
    let network: NetworkSummary
    let isSelected: Bool
    let isChecked: Bool
    let nameMinWidth: CGFloat
    let driverWidth: CGFloat
    let scopeWidth: CGFloat
    let containersWidth: CGFloat
    let idWidth: CGFloat
    let actionsWidth: CGFloat
    let onSelect: () -> Void
    let onToggleCheck: () -> Void
    let onRemove: () -> Void

    @State private var hovered = false

    var body: some View {
        HStack(spacing: 6) {
            if network.isDefaultNetwork {
                Spacer().frame(width: 16)
            } else {
                TableCheckbox(state: isChecked ? .checked : .unchecked, action: onToggleCheck)
            }

            ResourceRowIcon(
                systemImage: "network",
                tint: network.isDefaultNetwork ? Color.ctp.muted : Color.ctp.accent
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(verbatim: network.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.ctp.text)
                        .lineLimit(1)
                    if network.isDefaultNetwork {
                        Text("system", bundle: .l10n)
                            .font(.caption2)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.ctp.muted.opacity(0.15))
                            .clipShape(Capsule())
                            .foregroundStyle(Color.ctp.muted)
                    }
                }
                Text(verbatim: containersSubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(network.containerCount > 0 ? Color.ctp.ok : Color.ctp.muted)
                    .lineLimit(1)
            }
            .frame(minWidth: nameMinWidth, maxWidth: .infinity, alignment: .leading)

            Spacer().frame(width: 10)

            Text(verbatim: network.driver)
                .font(.system(size: 12))
                .foregroundStyle(Color.ctp.muted)
                .lineLimit(1)
                .frame(width: driverWidth, alignment: .leading)

            Spacer().frame(width: 10)

            Text(verbatim: network.scope)
                .font(.system(size: 12))
                .foregroundStyle(Color.ctp.muted)
                .lineLimit(1)
                .frame(width: scopeWidth, alignment: .leading)

            Spacer().frame(width: 10)

            Text(verbatim: "\(network.containerCount)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.ctp.text)
                .frame(width: containersWidth, alignment: .leading)

            Spacer().frame(width: 10)

            Text(verbatim: network.shortID)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.ctp.muted)
                .lineLimit(1)
                .frame(width: idWidth, alignment: .leading)

            Spacer().frame(width: 10)

            HStack(spacing: 6) {
                if !network.isDefaultNetwork {
                    IconActionButton(systemImage: "trash", tint: Color.ctp.err, help: "Remove", action: onRemove)
                } else {
                    Spacer().frame(width: 28)
                }
                SectionMenuButton {
                    Button { copyToPasteboard(network.name) } label: {
                        Label { Text("Copy Name", bundle: .l10n) } icon: { Image(systemName: "doc.on.doc") }
                    }
                    Button { copyToPasteboard(network.id) } label: {
                        Label { Text("Copy Network ID", bundle: .l10n) } icon: { Image(systemName: "number") }
                    }
                    if !network.isDefaultNetwork {
                        Divider()
                        Button(role: .destructive, action: onRemove) {
                            Label { Text("Remove", bundle: .l10n) } icon: { Image(systemName: "trash") }
                        }
                    }
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

    private var containersSubtitle: String {
        if network.containerCount == 1 {
            return String(localized: "1 container connected", bundle: .l10n)
        }
        return String(localized: "\(String(network.containerCount)) containers connected", bundle: .l10n)
    }
}

extension NetworkSummary {
    var isDefaultNetwork: Bool {
        NetworksStore.isDefaultNetworkName(name)
    }

    var shortID: String {
        let raw = id.hasPrefix("sha256:") ? String(id.dropFirst(7)) : id
        return String(raw.prefix(12))
    }
}
