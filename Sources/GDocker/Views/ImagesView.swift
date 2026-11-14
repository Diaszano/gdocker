import Foundation
import GDockerCore
import SwiftUI

struct ImagesView: View {
    @Environment(ImagesStore.self) private var store
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
        .searchable(text: $store.searchText, prompt: Text("Search images", bundle: .l10n))
        .navigationTitle(Text("Images", bundle: .l10n))
        .task {
            await store.refresh()
        }
        .confirmationDialog(
            Text("Remove image?", bundle: .l10n),
            isPresented: $confirmRemove,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                if let selected = store.selected {
                    Task { await store.remove(id: selected.id) }
                }
            } label: {
                Text("Remove", bundle: .l10n)
            }
        } message: {
            if let selected = store.selected {
                Text(verbatim: String(localized: "The image '\(selected.formattedTags)' will be removed permanently.", bundle: .l10n))
            } else {
                Text("The selected image will be removed permanently.", bundle: .l10n)
            }
        }
        .confirmationDialog(
            Text("Prune unused images?", bundle: .l10n),
            isPresented: $confirmPrune,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                Task { await store.prune() }
            } label: {
                Text("Prune Images", bundle: .l10n)
            }
        } message: {
            Text("All dangling and unused images will be removed permanently.", bundle: .l10n)
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
                Text("Images", bundle: .l10n)
                    .font(.title2.bold())
                Text(verbatim: subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.ctp.muted)
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
            .help(Text("Refresh images", bundle: .l10n))

            Button {
                confirmPrune = true
            } label: {
                Label {
                    Text("Prune Images", bundle: .l10n)
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
            .disabled(store.selected == nil)
            .keyboardShortcut(.delete, modifiers: [])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var subtitle: String {
        if store.searchText.isEmpty {
            if store.count == 1 {
                return String(localized: "\(String(store.count)) image", bundle: .l10n)
            } else {
                return String(localized: "\(String(store.count)) images", bundle: .l10n)
            }
        } else {
            return String(localized: "\(String(store.filteredImages.count)) of \(String(store.count))", bundle: .l10n)
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
                    Text("No Images", bundle: .l10n)
                } icon: {
                    Image(systemName: "square.stack.3d.up")
                }
            } description: {
                Text("No Docker images found.", bundle: .l10n)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.filteredImages.isEmpty {
            ContentUnavailableView.search(text: store.searchText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(store.filteredImages, selection: $store.selectedID) {
                TableColumn(String(localized: "Repository / Tag", bundle: .l10n)) { image in
                    HStack(spacing: 8) {
                        Image(systemName: "square.stack.3d.up")
                            .foregroundStyle(image.isDangling ? Color.ctp.muted : Color.ctp.accent)
                        Text(verbatim: image.formattedTags)
                            .fontWeight(image.isDangling ? .regular : .medium)
                            .foregroundStyle(image.isDangling ? Color.ctp.muted : .primary)
                    }
                }
                TableColumn(String(localized: "Image ID", bundle: .l10n)) { image in
                    Text(verbatim: image.shortID)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(Color.ctp.muted)
                }
                .width(min: 100, ideal: 120, max: 140)
                TableColumn(String(localized: "Size", bundle: .l10n)) { image in
                    Text(verbatim: image.formattedSize)
                        .monospacedDigit()
                }
                .width(min: 70, ideal: 90, max: 120)
                TableColumn(String(localized: "Created", bundle: .l10n)) { image in
                    Text(verbatim: image.formattedCreated)
                        .foregroundStyle(Color.ctp.muted)
                }
                .width(min: 120, ideal: 150, max: 200)
            }
            .contextMenu(forSelectionType: String.self) { selectedIDs in
                if let id = selectedIDs.first, let image = store.all.first(where: { $0.id == id }) {
                    Button(role: .destructive) {
                        store.selectedID = image.id
                        confirmRemove = true
                    } label: {
                        Text("Remove", bundle: .l10n)
                    }
                }
            }
        }
    }
}

extension ImageSummary {
    var shortID: String {
        let raw = id.hasPrefix("sha256:") ? String(id.dropFirst(7)) : id
        return String(raw.prefix(12))
    }

    var isDangling: Bool {
        repoTags.isEmpty || (repoTags.count == 1 && repoTags[0] == "<none>:<none>")
    }

    var formattedTags: String {
        if isDangling {
            return "<none>:<none>"
        }
        return repoTags.joined(separator: ", ")
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var formattedCreated: String {
        guard created > 0 else { return "—" }
        let date = Date(timeIntervalSince1970: TimeInterval(created))
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
