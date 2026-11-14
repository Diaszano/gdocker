import Foundation
import GDockerCore
import SwiftUI

struct ImagesView: View {
    @Environment(ImagesStore.self) private var store
    @Environment(ContainersStore.self) private var containersStore
    @State private var confirmRemoveTarget: ImageSummary?
    @State private var confirmBulkRemove = false
    @State private var confirmPrune = false
    @State private var pruneAllUnused = false

    @State private var nameMinWidth: CGFloat = 220
    @State private var idWidth: CGFloat = 128
    @State private var sizeWidth: CGFloat = 84
    @State private var createdWidth: CGFloat = 136
    private let actionsWidth: CGFloat = 68

    private var visibleImages: [ImageSummary] {
        store.filteredImages(containers: containersStore.all)
    }

    private var selectAllState: TableCheckState {
        let visible = visibleImages.map(\.id)
        guard !visible.isEmpty else { return .unchecked }
        let checked = visible.filter { store.selectedIDs.contains($0) }.count
        if checked == 0 { return .unchecked }
        return checked == visible.count ? .checked : .indeterminate
    }

    private var minTableWidth: CGFloat {
        40 + 22 + 28 + nameMinWidth + idWidth + sizeWidth + createdWidth + actionsWidth + 96
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
            Text("Remove image?", bundle: .l10n),
            isPresented: Binding(get: { confirmRemoveTarget != nil }, set: { if !$0 { confirmRemoveTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                if let target = confirmRemoveTarget {
                    confirmRemoveTarget = nil
                    Task { await store.remove(id: target.id) }
                }
            } label: { Text("Remove", bundle: .l10n) }
        } message: {
            if let target = confirmRemoveTarget {
                Text(verbatim: String(localized: "The image '\(target.formattedTags)' will be removed permanently.", bundle: .l10n))
            } else {
                Text("The selected image will be removed permanently.", bundle: .l10n)
            }
        }
        .confirmationDialog(
            Text("Remove selected images?", bundle: .l10n),
            isPresented: $confirmBulkRemove,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                let ids = store.selectedIDs
                Task { await store.remove(ids: ids) }
            } label: { Text("Remove", bundle: .l10n) }
        } message: {
            Text(verbatim: String(localized: "\(String(store.selectedIDs.count)) selected images will be removed permanently.", bundle: .l10n))
        }
        .confirmationDialog(
            Text("Prune unused images?", bundle: .l10n),
            isPresented: $confirmPrune,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                let all = pruneAllUnused
                Task { await store.prune(all: all) }
            } label: { Text("Prune Images", bundle: .l10n) }
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
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Images", bundle: .l10n)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.ctp.text)
                    Text(verbatim: subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.ctp.muted)
                }
                Spacer()

                TableSearchField(text: $store.searchText, prompt: String(localized: "Search images", bundle: .l10n), width: 230)

                IconActionButton(
                    systemImage: "arrow.clockwise",
                    help: LocalizedStringKey(String(localized: "Refresh images", bundle: .l10n))
                ) {
                    Task { await store.refresh() }
                }

                IconActionButton(
                    systemImage: "trash.slash",
                    tint: Color.ctp.err,
                    help: LocalizedStringKey(String(localized: "Prune Images", bundle: .l10n))
                ) {
                    pruneAllUnused = false
                    confirmPrune = true
                }

                SectionMenuButton(help: LocalizedStringKey(String(localized: "Section actions", bundle: .l10n))) {
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        Label { Text("Refresh", bundle: .l10n) } icon: { Image(systemName: "arrow.clockwise") }
                    }
                    Button(role: .destructive) {
                        pruneAllUnused = false
                        confirmPrune = true
                    } label: {
                        Label { Text("Prune dangling images", bundle: .l10n) } icon: { Image(systemName: "trash.slash") }
                    }
                    Button(role: .destructive) {
                        pruneAllUnused = true
                        confirmPrune = true
                    } label: {
                        Label { Text("Prune all unused images", bundle: .l10n) } icon: { Image(systemName: "trash") }
                    }
                }
            }

            HStack(spacing: 8) {
                FilterPill(title: LocalizedStringKey(String(localized: "All", bundle: .l10n)), dotColor: nil, isSelected: store.filter == .all) {
                    store.filter = .all
                }
                FilterPill(title: LocalizedStringKey(String(localized: "In use", bundle: .l10n)), dotColor: Color.ctp.ok, isSelected: store.filter == .inUse) {
                    store.filter = .inUse
                }
                FilterPill(title: LocalizedStringKey(String(localized: "Untagged", bundle: .l10n)), dotColor: Color.ctp.warn, isSelected: store.filter == .dangling) {
                    store.filter = .dangling
                }
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var content: some View {
        let items = visibleImages
        if !containersStore.connected || store.all.isEmpty || items.isEmpty {
            ResourceEmptyState(
                connected: containersStore.connected,
                isAllEmpty: store.all.isEmpty,
                searchText: store.searchText,
                emptyTitle: String(localized: "No Images", bundle: .l10n),
                emptySystemImage: "square.stack.3d.up",
                emptyDescription: String(localized: "No Docker images found.", bundle: .l10n)
            )
        } else {
            GeometryReader { geo in
                ScrollView(.horizontal) {
                    VStack(spacing: 0) {
                        tableHeader
                        Divider().overlay(Color.ctp.muted.opacity(0.18))
                        ScrollView(.vertical) {
                            LazyVStack(spacing: 0) {
                                ForEach(items) { image in
                                    let usageCount = store.containerUsageCount(for: image, containers: containersStore.all)
                                    ImageRow(
                                        image: image,
                                        usageCount: usageCount,
                                        isSelected: store.selectedID == image.id,
                                        isChecked: store.selectedIDs.contains(image.id),
                                        nameMinWidth: nameMinWidth,
                                        idWidth: idWidth,
                                        sizeWidth: sizeWidth,
                                        createdWidth: createdWidth,
                                        actionsWidth: actionsWidth,
                                        onSelect: { store.selectedID = image.id },
                                        onToggleCheck: { toggleCheck(image.id) },
                                        onRemove: { confirmRemoveTarget = image },
                                        onForceRemove: { Task { await store.remove(id: image.id, force: true) } }
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
            Spacer().frame(width: 30)

            Text("Repository / Tag", bundle: .l10n)
                .frame(minWidth: nameMinWidth, maxWidth: .infinity, alignment: .leading)
            ColumnResizeDivider(width: $nameMinWidth, minWidth: 180)

            Text("Image ID", bundle: .l10n)
                .frame(width: idWidth, alignment: .leading)
            ColumnResizeDivider(width: $idWidth, minWidth: 100)

            Text("Size", bundle: .l10n)
                .frame(width: sizeWidth, alignment: .leading)
            ColumnResizeDivider(width: $sizeWidth, minWidth: 72)

            Text("Created", bundle: .l10n)
                .frame(width: createdWidth, alignment: .leading)
            ColumnResizeDivider(width: $createdWidth, minWidth: 100)

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

    private func toggleCheck(_ id: String) {
        if store.selectedIDs.contains(id) {
            store.selectedIDs.remove(id)
        } else {
            store.selectedIDs.insert(id)
        }
    }

    private func toggleSelectAll() {
        let visible = visibleImages.map(\.id)
        if selectAllState == .checked {
            store.selectedIDs.subtract(visible)
        } else {
            store.selectedIDs.formUnion(visible)
        }
    }

    private var subtitle: String {
        if store.searchText.isEmpty && store.filter == .all {
            if store.count == 1 {
                return String(localized: "\(String(store.count)) image", bundle: .l10n)
            } else {
                return String(localized: "\(String(store.count)) images", bundle: .l10n)
            }
        } else {
            return String(localized: "\(String(visibleImages.count)) of \(String(store.count))", bundle: .l10n)
        }
    }
}

private struct ImageRow: View {
    let image: ImageSummary
    let usageCount: Int
    let isSelected: Bool
    let isChecked: Bool
    let nameMinWidth: CGFloat
    let idWidth: CGFloat
    let sizeWidth: CGFloat
    let createdWidth: CGFloat
    let actionsWidth: CGFloat
    let onSelect: () -> Void
    let onToggleCheck: () -> Void
    let onRemove: () -> Void
    let onForceRemove: () -> Void

    @State private var hovered = false

    var body: some View {
        HStack(spacing: 6) {
            TableCheckbox(state: isChecked ? .checked : .unchecked, action: onToggleCheck)

            ResourceRowIcon(
                systemImage: "square.stack.3d.up",
                tint: image.isDangling ? Color.ctp.muted : Color.ctp.accent
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: image.formattedTags)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(image.isDangling ? Color.ctp.muted : Color.ctp.text)
                    .lineLimit(1)
                Text(verbatim: usageSubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(usageCount > 0 ? Color.ctp.ok : Color.ctp.muted)
                    .lineLimit(1)
            }
            .frame(minWidth: nameMinWidth, maxWidth: .infinity, alignment: .leading)

            Spacer().frame(width: 10)

            Text(verbatim: "sha256:\(image.shortID)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.ctp.muted)
                .lineLimit(1)
                .frame(width: idWidth, alignment: .leading)

            Spacer().frame(width: 10)

            Text(verbatim: image.formattedSize)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.ctp.text)
                .lineLimit(1)
                .frame(width: sizeWidth, alignment: .leading)

            Spacer().frame(width: 10)

            Text(verbatim: image.formattedCreated)
                .font(.system(size: 11))
                .foregroundStyle(Color.ctp.muted)
                .lineLimit(1)
                .frame(width: createdWidth, alignment: .leading)

            Spacer().frame(width: 10)

            HStack(spacing: 6) {
                IconActionButton(systemImage: "trash", tint: Color.ctp.err, help: "Remove", action: onRemove)
                SectionMenuButton {
                    Button { copyToPasteboard(image.id) } label: {
                        Label { Text("Copy Image ID", bundle: .l10n) } icon: { Image(systemName: "doc.on.doc") }
                    }
                    Divider()
                    Button(role: .destructive, action: onRemove) {
                        Label { Text("Remove", bundle: .l10n) } icon: { Image(systemName: "trash") }
                    }
                    Button(role: .destructive, action: onForceRemove) {
                        Label { Text("Force remove", bundle: .l10n) } icon: { Image(systemName: "trash.fill") }
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

    private var usageSubtitle: String {
        if image.isDangling {
            return String(localized: "Untagged", bundle: .l10n)
        }
        if usageCount == 1 {
            return String(localized: "In use by 1 container", bundle: .l10n)
        }
        if usageCount > 1 {
            return String(localized: "In use by \(String(usageCount)) containers", bundle: .l10n)
        }
        return String(localized: "Unused", bundle: .l10n)
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
