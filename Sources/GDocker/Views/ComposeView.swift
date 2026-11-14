import Foundation
import GDockerCore
import SwiftUI

struct ComposeView: View {
    @Environment(ComposeStore.self) private var store
    @Environment(ContainersStore.self) private var containersStore
    @State private var confirmDown = false
    @State private var confirmCleanDown = false
    @State private var projectForDown: ComposeProject?

    @State private var nameMinWidth: CGFloat = 200
    @State private var statusWidth: CGFloat = 132
    @State private var servicesWidth: CGFloat = 76
    @State private var dirWidth: CGFloat = 240
    private let actionsWidth: CGFloat = 98

    private var minTableWidth: CGFloat {
        40 + 28 + nameMinWidth + statusWidth + servicesWidth + dirWidth + actionsWidth + 90
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if !store.isComposeAvailable {
                unavailableBanner
            }
            content
        }
        .background(Color.ctp.bg)
        .task { await store.refresh() }
        .task(id: containersStore.revision) { await store.refresh() }
        .confirmationDialog(
            Text("Stop compose stack?", bundle: .l10n),
            isPresented: $confirmDown,
            titleVisibility: .visible
        ) {
            if let project = projectForDown {
                Button(role: .destructive) {
                    Task { await store.down(project: project, removeVolumes: false) }
                } label: {
                    Text("Down", bundle: .l10n)
                }
                Button(role: .destructive) {
                    Task { await store.down(project: project, removeVolumes: true) }
                } label: {
                    Text("Down and Remove Volumes", bundle: .l10n)
                }
            }
            Button(role: .cancel) { } label: { Text("Cancel", bundle: .l10n) }
        } message: {
            Text("This will stop and remove containers for this project.", bundle: .l10n)
        }
        .confirmationDialog(
            Text("Clean stopped compose projects?", bundle: .l10n),
            isPresented: $confirmCleanDown,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                Task { await store.cleanDownProjects() }
            } label: {
                Text("Clean Stopped", bundle: .l10n)
            }
        } message: {
            Text("Down projects with no remaining containers will be removed from the Compose list.", bundle: .l10n)
        }
        .alert(
            Text("Compose error", bundle: .l10n),
            isPresented: Binding(get: { store.lastError != nil }, set: { if !$0 { store.lastError = nil } })
        ) {
            Button { } label: { Text("OK", bundle: .l10n) }
        } message: {
            Text(verbatim: store.lastError ?? "")
        }
    }

    private var canAct: Bool { store.isComposeAvailable && !store.isPerformingAction }

    private func askDown(_ project: ComposeProject) {
        projectForDown = project
        confirmDown = true
    }

    private var header: some View {
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Compose", bundle: .l10n)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.ctp.text)
                    Text(verbatim: subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.ctp.muted)
                }
                Spacer()

                TableSearchField(text: $store.searchText, prompt: String(localized: "Search compose projects", bundle: .l10n), width: 260)

                IconActionButton(
                    systemImage: "arrow.clockwise",
                    help: LocalizedStringKey(String(localized: "Refresh compose projects", bundle: .l10n))
                ) {
                    Task { await store.refresh() }
                }

                IconActionButton(
                    systemImage: "trash.slash",
                    tint: store.downCount > 0 ? Color.ctp.err : Color.ctp.muted,
                    help: LocalizedStringKey(String(localized: "Clean stopped compose projects", bundle: .l10n))
                ) {
                    confirmCleanDown = true
                }
                .disabled(store.downCount == 0)

                SectionMenuButton(help: LocalizedStringKey(String(localized: "Section actions", bundle: .l10n))) {
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        Label { Text("Refresh", bundle: .l10n) } icon: { Image(systemName: "arrow.clockwise") }
                    }
                    Button(role: .destructive) {
                        confirmCleanDown = true
                    } label: {
                        Label { Text("Clean stopped compose projects", bundle: .l10n) } icon: { Image(systemName: "trash.slash") }
                    }
                    .disabled(store.downCount == 0)
                }
            }

            HStack(spacing: 8) {
                FilterPill(title: LocalizedStringKey(String(localized: "All", bundle: .l10n)), dotColor: nil, isSelected: store.filter == .all) {
                    store.filter = .all
                }
                FilterPill(title: "Running", dotColor: Color.ctp.ok, isSelected: store.filter == .running) {
                    store.filter = .running
                }
                FilterPill(title: "Partially running", dotColor: Color.ctp.warn, isSelected: store.filter == .partial) {
                    store.filter = .partial
                }
                FilterPill(title: "Stopped", dotColor: Color.ctp.muted, isSelected: store.filter == .stopped) {
                    store.filter = .stopped
                }
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 12)
    }

    private var subtitle: String {
        String(localized: "\(String(store.count)) projects · \(String(store.activeCount)) active", bundle: .l10n)
    }

    private var unavailableBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.ctp.warn)
            VStack(alignment: .leading, spacing: 2) {
                Text("Docker Compose CLI not found.", bundle: .l10n).fontWeight(.medium)
                Text("The docker compose binary was not detected on this system.", bundle: .l10n)
                    .font(.caption)
                    .foregroundStyle(Color.ctp.muted)
            }
            Spacer()
        }
        .padding(10)
        .background(Color.ctp.warn.opacity(0.15))
    }

    @ViewBuilder
    private var content: some View {
        if store.filteredProjects.isEmpty {
            if store.projects.isEmpty && store.searchText.isEmpty {
                ContentUnavailableView {
                    Label {
                        Text("No Compose Projects", bundle: .l10n)
                    } icon: {
                        Image(systemName: "square.stack.3d.forward.dottedline")
                    }
                } description: {
                    Text("Compose projects will appear here when containers with compose labels are detected.", bundle: .l10n)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView {
                    Label {
                        Text("No matching compose projects", bundle: .l10n)
                    } icon: {
                        Image(systemName: "magnifyingglass")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            VSplitView {
                GeometryReader { geo in
                    ScrollView(.horizontal) {
                        VStack(spacing: 0) {
                            tableHeader
                            Divider().overlay(Color.ctp.muted.opacity(0.18))
                            ScrollView(.vertical) {
                                LazyVStack(spacing: 0) {
                                    ForEach(store.filteredProjects) { project in
                                        ComposeRow(
                                            project: project,
                                            isSelected: store.selectedProjectName == project.name,
                                            canAct: canAct,
                                            nameMinWidth: nameMinWidth,
                                            statusWidth: statusWidth,
                                            servicesWidth: servicesWidth,
                                            dirWidth: dirWidth,
                                            actionsWidth: actionsWidth,
                                            onSelect: { store.selectedProjectName = project.name },
                                            onUp: { Task { await store.up(project: project) } },
                                            onDown: { askDown(project) },
                                            onForget: { Task { await store.forget(project: project) } }
                                        )
                                        Divider().overlay(Color.ctp.muted.opacity(0.1))
                                    }
                                }
                            }
                        }
                        .frame(minWidth: max(geo.size.width, minTableWidth), maxHeight: .infinity, alignment: .topLeading)
                    }
                }
                .frame(minHeight: 160)

                Group {
                    if let selected = store.selected {
                        detail(selected)
                    } else {
                        Text("Select a compose project", bundle: .l10n).foregroundStyle(Color.ctp.muted)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 160, maxHeight: .infinity)
            }
        }
    }

    private var tableHeader: some View {
        HStack(spacing: 6) {
            Spacer().frame(width: 28)

            Text("Project", bundle: .l10n)
                .frame(minWidth: nameMinWidth, maxWidth: .infinity, alignment: .leading)
            ColumnResizeDivider(width: $nameMinWidth, minWidth: 160)

            Text("Status", bundle: .l10n)
                .frame(width: statusWidth, alignment: .leading)
            ColumnResizeDivider(width: $statusWidth, minWidth: 108)

            Text("Services", bundle: .l10n)
                .frame(width: servicesWidth, alignment: .leading)
            ColumnResizeDivider(width: $servicesWidth, minWidth: 68)

            Text("Working Directory", bundle: .l10n)
                .frame(width: dirWidth, alignment: .leading)
            ColumnResizeDivider(width: $dirWidth, minWidth: 140)

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

    private func detail(_ project: ComposeProject) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(verbatim: project.name).font(.title3.bold())
                ComposeStatusBadge(status: project.status)
                Spacer()
                Button {
                    Task { await store.up(project: project) }
                } label: {
                    Label {
                        Text("Up", bundle: .l10n)
                    } icon: {
                        Image(systemName: "play.fill")
                    }
                }
                .disabled(!canAct)
                Button(role: .destructive) {
                    askDown(project)
                } label: {
                    Label {
                        Text("Down", bundle: .l10n)
                    } icon: {
                        Image(systemName: "stop.fill")
                    }
                }
                .disabled(!canAct || project.status == .down)
                if project.status == .down {
                    Button {
                        Task { await store.forget(project: project) }
                    } label: {
                        Text("Forget Project", bundle: .l10n)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: project.workingDir).font(.caption).foregroundStyle(Color.ctp.muted)
                ForEach(project.configFiles, id: \.self) { file in
                    Text(verbatim: file).font(.caption.monospaced()).foregroundStyle(Color.ctp.muted)
                }
            }
            .textSelection(.enabled)
            Table(project.services) {
                TableColumn(String(localized: "Service", bundle: .l10n)) { service in
                    Text(verbatim: service.name).fontWeight(.medium)
                }
                TableColumn(String(localized: "Container", bundle: .l10n)) { service in
                    Text(verbatim: service.containerID.map { String($0.prefix(12)) } ?? "-")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(Color.ctp.muted)
                }
                .width(min: 100, ideal: 120, max: 140)
                TableColumn(String(localized: "State", bundle: .l10n)) { service in
                    HStack(spacing: 6) {
                        StatusDot(kind: service.statusKind ?? .stopped)
                        Text(verbatim: service.state ?? "-").foregroundStyle(Color.ctp.muted)
                    }
                }
            }
        }
        .padding(16)
    }
}

private struct ComposeRow: View {
    let project: ComposeProject
    let isSelected: Bool
    let canAct: Bool
    let nameMinWidth: CGFloat
    let statusWidth: CGFloat
    let servicesWidth: CGFloat
    let dirWidth: CGFloat
    let actionsWidth: CGFloat
    let onSelect: () -> Void
    let onUp: () -> Void
    let onDown: () -> Void
    let onForget: () -> Void

    @State private var hovered = false

    private var activeServicesCount: Int {
        project.services.filter { $0.statusKind == .running }.count
    }

    var body: some View {
        HStack(spacing: 6) {
            ResourceRowIcon(
                systemImage: "square.stack.3d.forward.dottedline",
                tint: project.isActive ? Color.ctp.accent : Color.ctp.muted
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: project.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.ctp.text)
                    .lineLimit(1)
                Text(verbatim: String(localized: "\(String(activeServicesCount)) of \(String(project.services.count)) services active", bundle: .l10n))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.ctp.muted)
                    .lineLimit(1)
            }
            .frame(minWidth: nameMinWidth, maxWidth: .infinity, alignment: .leading)

            Spacer().frame(width: 10)

            ComposeStatusBadge(status: project.status)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: statusWidth, alignment: .leading)

            Spacer().frame(width: 10)

            Text(verbatim: "\(project.services.count)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.ctp.text)
                .frame(width: servicesWidth, alignment: .leading)

            Spacer().frame(width: 10)

            Text(verbatim: project.workingDir)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.ctp.muted)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: dirWidth, alignment: .leading)

            Spacer().frame(width: 10)

            HStack(spacing: 6) {
                IconActionButton(
                    systemImage: project.isActive ? "arrow.clockwise" : "play.fill",
                    help: LocalizedStringKey(String(localized: "Start stack", bundle: .l10n)),
                    action: onUp
                )
                .disabled(!canAct)

                if project.status == .down {
                    IconActionButton(
                        systemImage: "trash",
                        tint: Color.ctp.err,
                        help: LocalizedStringKey(String(localized: "Forget Project", bundle: .l10n)),
                        action: onForget
                    )
                } else {
                    IconActionButton(
                        systemImage: "stop.fill",
                        help: LocalizedStringKey(String(localized: "Stop stack", bundle: .l10n)),
                        action: onDown
                    )
                    .disabled(!canAct)
                }

                SectionMenuButton {
                    Button(action: onUp) {
                        Label { Text("Start stack", bundle: .l10n) } icon: { Image(systemName: "play.fill") }
                    }
                    .disabled(!canAct)
                    Button(role: .destructive, action: onDown) {
                        Label { Text("Stop stack", bundle: .l10n) } icon: { Image(systemName: "stop.fill") }
                    }
                    .disabled(!canAct || project.status == .down)
                    Divider()
                    Button { copyToPasteboard(project.workingDir) } label: {
                        Label { Text("Copy path", bundle: .l10n) } icon: { Image(systemName: "doc.on.doc") }
                    }
                    if project.status == .down {
                        Button(role: .destructive, action: onForget) {
                            Label { Text("Forget Project", bundle: .l10n) } icon: { Image(systemName: "trash") }
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
}

private struct ComposeStatusBadge: View {
    let status: ComposeStatus

    var body: some View {
        StatusBadge(color: color, label: labelKey)
    }

    private var labelKey: LocalizedStringKey {
        switch status {
        case .running: "Running"
        case .partiallyRunning: "Partially running"
        case .stopped: "Stopped"
        case .down: "Down"
        }
    }

    private var color: Color {
        switch status {
        case .running: Color.ctp.ok
        case .partiallyRunning: Color.ctp.warn
        case .stopped: Color.ctp.muted
        case .down: Color.ctp.accent
        }
    }
}
