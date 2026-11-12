import Foundation
import GDockerCore
import SwiftUI

struct NetworksView: View {
    @Environment(NetworksStore.self) private var store
    @Environment(ContainersStore.self) private var containersStore
    @State private var confirmRemove = false
    @State private var confirmPrune = false

    private var canRemoveSelected: Bool {
        guard let selected = store.selected else { return false }
        return !selected.isDefaultNetwork
    }

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .searchable(text: $store.searchText, prompt: Text("Search networks", bundle: .l10n))
        .navigationTitle(Text("Networks", bundle: .l10n))
        .task {
            await store.refresh()
        }
        .confirmationDialog(
            Text("Remove network?", bundle: .l10n),
            isPresented: $confirmRemove,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                if let selected = store.selected, !selected.isDefaultNetwork {
                    Task { await store.remove(id: selected.id) }
                }
            } label: {
                Text("Remove", bundle: .l10n)
            }
        } message: {
            if let selected = store.selected {
                Text(verbatim: String(localized: "The network '\(selected.name)' will be removed permanently.", bundle: .l10n))
            } else {
                Text("The selected network will be removed permanently.", bundle: .l10n)
            }
        }
        .confirmationDialog(
            Text("Prune unused networks?", bundle: .l10n),
            isPresented: $confirmPrune,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                Task { await store.prune() }
            } label: {
                Text("Prune Networks", bundle: .l10n)
            }
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
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Networks", bundle: .l10n)
                    .font(.title2.bold())
                Text(verbatim: subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await store.refresh() }
            } label: {
                Label {
                    Text("Refresh", bundle: .l10n)
                } icon: {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .help(Text("Refresh networks", bundle: .l10n))

            Button {
                confirmPrune = true
            } label: {
                Label {
                    Text("Prune Networks", bundle: .l10n)
                } icon: {
                    Image(systemName: "trash.slash")
                }
            }

            Button(role: .destructive) {
                confirmRemove = true
            } label: {
                Label {
                    Text("Remove", bundle: .l10n)
                } icon: {
                    Image(systemName: "trash")
                }
            }
            .disabled(!canRemoveSelected)
            .keyboardShortcut(.delete, modifiers: [])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var subtitle: String {
        if store.searchText.isEmpty {
            if store.count == 1 {
                return String(localized: "\(String(store.count)) network", bundle: .l10n)
            } else {
                return String(localized: "\(String(store.count)) networks", bundle: .l10n)
            }
        } else {
            return String(localized: "\(String(store.filteredNetworks.count)) of \(String(store.count))", bundle: .l10n)
        }
    }

    @ViewBuilder
    private var content: some View {
        @Bindable var store = store
        if !containersStore.connected {
            ContentUnavailableView {
                Label {
                    Text("Docker disconnected", bundle: .l10n)
                } icon: {
                    Image(systemName: "bolt.slash")
                }
            } description: {
                Text("Docker is not reachable. Ensure Docker Desktop or Docker Engine is running.", bundle: .l10n)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.all.isEmpty {
            ContentUnavailableView {
                Label {
                    Text("No Networks", bundle: .l10n)
                } icon: {
                    Image(systemName: "network")
                }
            } description: {
                Text("No Docker networks found.", bundle: .l10n)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.filteredNetworks.isEmpty {
            ContentUnavailableView.search(text: store.searchText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(store.filteredNetworks, selection: $store.selectedID) {
                TableColumn("Name") { network in
                    HStack(spacing: 8) {
                        Image(systemName: "network")
                            .foregroundStyle(Color.accentColor)
                        Text(verbatim: network.name)
                            .fontWeight(.medium)
                        if network.isDefaultNetwork {
                            Text("system", bundle: .l10n)
                                .font(.caption2)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.15))
                                .clipShape(Capsule())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                TableColumn("Network ID") { network in
                    Text(verbatim: network.shortID)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .width(min: 100, ideal: 120, max: 140)
                TableColumn("Driver") { network in
                    Text(verbatim: network.driver)
                        .foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 100, max: 120)
                TableColumn("Scope") { network in
                    Text(verbatim: network.scope)
                        .foregroundStyle(.secondary)
                }
                .width(min: 70, ideal: 90, max: 110)
                TableColumn("Containers") { network in
                    Text(verbatim: "\(network.containerCount)")
                        .monospacedDigit()
                }
                .width(min: 70, ideal: 90, max: 110)
            }
            .contextMenu(forSelectionType: String.self) { selectedIDs in
                if let id = selectedIDs.first, let network = store.all.first(where: { $0.id == id }) {
                    if !network.isDefaultNetwork {
                        Button(role: .destructive) {
                            store.selectedID = network.id
                            confirmRemove = true
                        } label: {
                            Text("Remove", bundle: .l10n)
                        }
                    }
                }
            }
        }
    }
}

extension NetworkSummary {
    var isDefaultNetwork: Bool {
        ["bridge", "host", "none"].contains(name.lowercased())
    }

    var shortID: String {
        let raw = id.hasPrefix("sha256:") ? String(id.dropFirst(7)) : id
        return String(raw.prefix(12))
    }
}
