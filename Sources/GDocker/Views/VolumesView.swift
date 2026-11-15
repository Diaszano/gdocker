import Foundation
import GDockerCore
import SwiftUI

@MainActor
private enum VolumeDateFormatters {
    static let isoWithFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

struct VolumesView: View {
    @Environment(VolumesStore.self) private var store
    @Environment(ContainersStore.self) private var containersStore
    @State private var confirmRemoveTarget: VolumeSummary?
    @State private var confirmBulkRemove = false
    @State private var confirmPrune = false

    @State private var nameMinWidth: CGFloat = 220
    @State private var driverWidth: CGFloat = 88
    @State private var scopeWidth: CGFloat = 84
    @State private var createdWidth: CGFloat = 136
    private let actionsWidth: CGFloat = 98

    private var selectAllState: TableCheckState {
        let visible = store.filteredVolumes.map(\.name)
        guard !visible.isEmpty else { return .unchecked }
        let checked = visible.filter { store.selectedIDs.contains($0) }.count
        if checked == 0 { return .unchecked }
        return checked == visible.count ? .checked : .indeterminate
    }

    private var minTableWidth: CGFloat {
        40 + 22 + 28 + nameMinWidth + driverWidth + scopeWidth + createdWidth + actionsWidth + 96
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
            Text("Remove volume?", bundle: .l10n),
            isPresented: Binding(get: { confirmRemoveTarget != nil }, set: { if !$0 { confirmRemoveTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                if let target = confirmRemoveTarget {
                    confirmRemoveTarget = nil
                    Task { await store.remove(name: target.name) }
                }
            } label: { Text("Remove", bundle: .l10n) }
        } message: {
            if let target = confirmRemoveTarget {
                Text(verbatim: String(localized: "The volume '\(target.name)' will be removed permanently. Any stored data will be lost.", bundle: .l10n))
            } else {
                Text("The selected volume will be removed permanently.", bundle: .l10n)
            }
        }
        .confirmationDialog(
            Text("Remove selected volumes?", bundle: .l10n),
            isPresented: $confirmBulkRemove,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                let names = store.selectedIDs
                Task { await store.remove(names: names) }
            } label: { Text("Remove", bundle: .l10n) }
        } message: {
            Text(verbatim: String(localized: "\(String(store.selectedIDs.count)) selected volumes will be removed permanently. Any stored data will be lost.", bundle: .l10n))
        }
        .confirmationDialog(
            Text("Prune unused volumes?", bundle: .l10n),
            isPresented: $confirmPrune,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                Task { await store.prune() }
            } label: { Text("Prune Volumes", bundle: .l10n) }
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
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Volumes", bundle: .l10n)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.ctp.text)
                    Text(verbatim: subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.ctp.muted)
                }
                Spacer()

                TableSearchField(text: $store.searchText, prompt: String(localized: "Search volumes", bundle: .l10n), width: 260)

                IconActionButton(
                    systemImage: "arrow.clockwise",
                    help: LocalizedStringKey(String(localized: "Refresh volumes", bundle: .l10n))
                ) {
                    Task { await store.refresh() }
                }

                IconActionButton(
                    systemImage: "trash.slash",
                    tint: Color.ctp.err,
                    help: LocalizedStringKey(String(localized: "Prune Volumes", bundle: .l10n))
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
                        Label { Text("Prune Volumes", bundle: .l10n) } icon: { Image(systemName: "trash.slash") }
                    }
                }
            }

            HStack(spacing: 8) {
                FilterPill(title: LocalizedStringKey(String(localized: "All", bundle: .l10n)), dotColor: nil, isSelected: store.filter == .all) {
                    store.filter = .all
                }
                FilterPill(title: LocalizedStringKey(String(localized: "Named", bundle: .l10n)), dotColor: Color.ctp.accent, isSelected: store.filter == .named) {
                    store.filter = .named
                }
                FilterPill(title: LocalizedStringKey(String(localized: "Anonymous", bundle: .l10n)), dotColor: Color.ctp.muted, isSelected: store.filter == .anonymous) {
                    store.filter = .anonymous
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
        let items = store.filteredVolumes
        if !containersStore.connected || store.all.isEmpty || items.isEmpty {
            ResourceEmptyState(
                connected: containersStore.connected,
                isAllEmpty: store.all.isEmpty,
                searchText: store.searchText,
                emptyTitle: String(localized: "No Volumes", bundle: .l10n),
                emptySystemImage: "externaldrive",
                emptyDescription: String(localized: "No Docker volumes found.", bundle: .l10n)
            )
        } else {
            GeometryReader { geo in
                ScrollView(.horizontal) {
                    VStack(spacing: 0) {
                        tableHeader
                        Divider().overlay(Color.ctp.muted.opacity(0.18))
                        ScrollView(.vertical) {
                            LazyVStack(spacing: 0) {
                                ForEach(items) { volume in
                                    VolumeRow(
                                        volume: volume,
                                        isSelected: store.selectedID == volume.name,
                                        isChecked: store.selectedIDs.contains(volume.name),
                                        isMounted: store.mountedVolumes.contains(volume.name),
                                        isMounting: store.mountingVolumes.contains(volume.name),
                                        nameMinWidth: nameMinWidth,
                                        driverWidth: driverWidth,
                                        scopeWidth: scopeWidth,
                                        createdWidth: createdWidth,
                                        actionsWidth: actionsWidth,
                                        onSelect: { store.selectedID = volume.name },
                                        onToggleCheck: { toggleCheck(volume.name) },
                                        onOpenInFinder: { Task { await store.openInFinder(name: volume.name) } },
                                        onUnmount: { Task { await store.unmount(name: volume.name) } },
                                        onRemove: { confirmRemoveTarget = volume },
                                        onForceRemove: { Task { await store.remove(name: volume.name, force: true) } }
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

    private func toggleCheck(_ name: String) {
        if store.selectedIDs.contains(name) {
            store.selectedIDs.remove(name)
        } else {
            store.selectedIDs.insert(name)
        }
    }

    private func toggleSelectAll() {
        let visible = store.filteredVolumes.map(\.name)
        if selectAllState == .checked {
            store.selectedIDs.subtract(visible)
        } else {
            store.selectedIDs.formUnion(visible)
        }
    }

    private var subtitle: String {
        if store.searchText.isEmpty && store.filter == .all {
            if store.count == 1 {
                return String(localized: "\(String(store.count)) volume", bundle: .l10n)
            } else {
                return String(localized: "\(String(store.count)) volumes", bundle: .l10n)
            }
        } else {
            return String(localized: "\(String(store.filteredVolumes.count)) of \(String(store.count))", bundle: .l10n)
        }
    }
}

private struct VolumeRow: View {
    let volume: VolumeSummary
    let isSelected: Bool
    let isChecked: Bool
    let isMounted: Bool
    let isMounting: Bool
    let nameMinWidth: CGFloat
    let driverWidth: CGFloat
    let scopeWidth: CGFloat
    let createdWidth: CGFloat
    let actionsWidth: CGFloat
    let onSelect: () -> Void
    let onToggleCheck: () -> Void
    let onOpenInFinder: () -> Void
    let onUnmount: () -> Void
    let onRemove: () -> Void
    let onForceRemove: () -> Void

    @State private var hovered = false

    private var isAnonymous: Bool { VolumesStore.isAnonymousVolume(volume.name) }

    var body: some View {
        HStack(spacing: 6) {
            TableCheckbox(state: isChecked ? .checked : .unchecked, action: onToggleCheck)

            ResourceRowIcon(
                systemImage: "externaldrive",
                tint: isAnonymous ? Color.ctp.muted : Color.ctp.accent
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: volume.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.ctp.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(verbatim: isAnonymous ? String(localized: "Anonymous volume", bundle: .l10n) : String(localized: "Named volume", bundle: .l10n))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.ctp.muted)
                        .lineLimit(1)
                    if isMounted {
                        Text("Mounted in Finder", bundle: .l10n)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.ctp.ok)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.ctp.ok.opacity(0.14)))
                    }
                }
            }
            .frame(minWidth: nameMinWidth, maxWidth: .infinity, alignment: .leading)

            Spacer().frame(width: 10)

            Text(verbatim: volume.driver)
                .font(.system(size: 12))
                .foregroundStyle(Color.ctp.muted)
                .lineLimit(1)
                .frame(width: driverWidth, alignment: .leading)

            Spacer().frame(width: 10)

            Text(verbatim: volume.scope)
                .font(.system(size: 12))
                .foregroundStyle(Color.ctp.muted)
                .lineLimit(1)
                .frame(width: scopeWidth, alignment: .leading)

            Spacer().frame(width: 10)

            Text(verbatim: volume.formattedCreated)
                .font(.system(size: 11))
                .foregroundStyle(Color.ctp.muted)
                .lineLimit(1)
                .frame(width: createdWidth, alignment: .leading)

            Spacer().frame(width: 10)

            HStack(spacing: 6) {
                if isMounting {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 28, height: 28)
                        .help(Text("Mounting volume...", bundle: .l10n))
                } else {
                    IconActionButton(
                        systemImage: isMounted ? "folder.fill" : "folder",
                        tint: isMounted ? Color.ctp.ok : Color.ctp.accent,
                        help: LocalizedStringKey(String(localized: "Open in Finder", bundle: .l10n)),
                        action: onOpenInFinder
                    )
                }
                IconActionButton(systemImage: "trash", tint: Color.ctp.err, help: "Remove", action: onRemove)
                SectionMenuButton {
                    Button(action: onOpenInFinder) {
                        Label { Text("Open in Finder", bundle: .l10n) } icon: { Image(systemName: "folder") }
                    }
                    .disabled(isMounting)
                    if isMounted {
                        Button(action: onUnmount) {
                            Label { Text("Unmount from Finder", bundle: .l10n) } icon: { Image(systemName: "eject") }
                        }
                    }
                    Button { copyToPasteboard(volume.name) } label: {
                        Label { Text("Copy Name", bundle: .l10n) } icon: { Image(systemName: "doc.on.doc") }
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
}

extension VolumeSummary {
    @MainActor
    var formattedCreated: String {
        guard let createdAt, !createdAt.isEmpty else { return "—" }

        if let date = VolumeDateFormatters.isoWithFraction.date(from: createdAt) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }

        if let date = VolumeDateFormatters.iso.date(from: createdAt) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }

        if let dotIndex = createdAt.firstIndex(of: ".") {
            let rest = createdAt[dotIndex...]
            if let endIdx = rest.firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" }) {
                let fracDigits = createdAt[createdAt.index(after: dotIndex)..<endIdx]
                let suffix = createdAt[endIdx...]
                let trimmed = String(createdAt[..<dotIndex]) + "." + String(fracDigits.prefix(3)) + String(suffix)
                if let date = VolumeDateFormatters.isoWithFraction.date(from: trimmed) {
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
