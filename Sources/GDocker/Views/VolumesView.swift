import Foundation
import GDockerCore
import SwiftUI

struct VolumesView: View {
    @Environment(VolumesStore.self) private var store
    @Environment(ContainersStore.self) private var containersStore
    @State private var confirmRemove = false
    @State private var confirmPrune = false

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .searchable(text: $store.searchText, prompt: Text("Search volumes", bundle: .l10n))
        .navigationTitle(Text("Volumes", bundle: .l10n))
        .task {
            await store.refresh()
        }
        .confirmationDialog(
            Text("Remove volume?", bundle: .l10n),
            isPresented: $confirmRemove,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                if let selected = store.selected {
                    Task { await store.remove(name: selected.name) }
                }
            } label: {
                Text("Remove", bundle: .l10n)
            }
        } message: {
            if let selected = store.selected {
                Text("The volume '\(selected.name)' will be removed permanently. Any stored data will be lost.", bundle: .l10n)
            } else {
                Text("The selected volume will be removed permanently.", bundle: .l10n)
            }
        }
        .confirmationDialog(
            Text("Prune unused volumes?", bundle: .l10n),
            isPresented: $confirmPrune,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                Task { await store.prune() }
            } label: {
                Text("Prune Volumes", bundle: .l10n)
            }
        } message: {
            Text("All unused volumes will be removed permanently. Any data in unused volumes will be lost.", bundle: .l10n)
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
                Text("Volumes", bundle: .l10n)
                    .font(.title2.bold())
                Text(verbatim: subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await store.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help(Text("Refresh volumes", bundle: .l10n))

            Button {
                confirmPrune = true
            } label: {
                Label("Prune Volumes…", systemImage: "trash.slash")
            }

            Button(role: .destructive) {
                confirmRemove = true
            } label: {
                Label("Remove", systemImage: "trash")
            }
            .disabled(store.selected == nil)
            .keyboardShortcut(.delete, modifiers: [])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var subtitle: String {
        if store.searchText.isEmpty {
            return store.count == 1 ? "1 volume" : "\(store.count) volumes"
        } else {
            return "\(store.filteredVolumes.count) of \(store.count)"
        }
    }

    @ViewBuilder
    private var content: some View {
        @Bindable var store = store
        if !containersStore.connected {
            ContentUnavailableView {
                Label {
                    Text("Docker Disconnected", bundle: .l10n)
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
                    Text("No Volumes", bundle: .l10n)
                } icon: {
                    Image(systemName: "externaldrive")
                }
            } description: {
                Text("No Docker volumes found.", bundle: .l10n)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.filteredVolumes.isEmpty {
            ContentUnavailableView.search(text: store.searchText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(store.filteredVolumes, selection: $store.selectedID) {
                TableColumn("Name") { volume in
                    HStack(spacing: 8) {
                        Image(systemName: "externaldrive")
                            .foregroundStyle(Color.accentColor)
                        Text(verbatim: volume.name)
                            .fontWeight(.medium)
                    }
                }
                TableColumn("Driver") { volume in
                    Text(verbatim: volume.driver)
                        .foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 100, max: 120)
                TableColumn("Scope") { volume in
                    Text(verbatim: volume.scope)
                        .foregroundStyle(.secondary)
                }
                .width(min: 70, ideal: 90, max: 110)
                TableColumn("Created") { volume in
                    Text(verbatim: volume.formattedCreated)
                        .foregroundStyle(.secondary)
                }
                .width(min: 120, ideal: 150, max: 200)
            }
            .contextMenu(forSelectionType: String.self) { selectedIDs in
                if let id = selectedIDs.first, let volume = store.all.first(where: { $0.name == id }) {
                    Button(role: .destructive) {
                        store.selectedID = volume.name
                        confirmRemove = true
                    } label: {
                        Text("Remove", bundle: .l10n)
                    }
                }
            }
        }
    }
}

extension VolumeSummary {
    var formattedCreated: String {
        guard let createdAt, !createdAt.isEmpty else { return "—" }
        let isoWithFraction = ISO8601DateFormatter()
        isoWithFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoWithFraction.date(from: createdAt) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: createdAt) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }

        if let dotIndex = createdAt.firstIndex(of: ".") {
            let rest = createdAt[dotIndex...]
            if let endIdx = rest.firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" }) {
                let fracDigits = createdAt[createdAt.index(after: dotIndex)..<endIdx]
                let suffix = createdAt[endIdx...]
                let trimmed = String(createdAt[..<dotIndex]) + "." + String(fracDigits.prefix(3)) + String(suffix)
                if let date = isoWithFraction.date(from: trimmed) {
                    return date.formatted(date: .abbreviated, time: .shortened)
                }
            }
        }

        if let timestamp = Double(createdAt), timestamp > 0 {
            let date = Date(timeIntervalSince1970: timestamp)
            return date.formatted(date: .abbreviated, time: .shortened)
        }

        return createdAt
    }
}
