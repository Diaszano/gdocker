import Foundation
import GDockerCore
import SwiftUI

struct ComposeView: View {
    @Environment(ComposeStore.self) private var store
    @Environment(ContainersStore.self) private var containersStore
    @State private var confirmDown = false
    @State private var projectForDown: ComposeProject?

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            header
            if !store.isComposeAvailable {
                unavailableBanner
            }
            Divider()
            content
        }
        .searchable(text: $store.searchText, prompt: Text("Search compose projects", bundle: .l10n))
        .navigationTitle(Text("Compose", bundle: .l10n))
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
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Compose", bundle: .l10n).font(.title2.bold())
                Text(verbatim: subtitle).font(.caption).foregroundStyle(.secondary)
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
            .help(Text("Refresh compose projects", bundle: .l10n))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var subtitle: String {
        String(
            localized: "\(String(store.count)) projects · \(String(store.activeCount)) active",
            bundle: .l10n
        )
    }

    private var unavailableBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("Docker Compose CLI not found.", bundle: .l10n).fontWeight(.medium)
                Text("The docker compose binary was not detected on this system.", bundle: .l10n)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(Color.yellow.opacity(0.15))
    }

    @ViewBuilder
    private var content: some View {
        @Bindable var store = store
        if store.filteredProjects.isEmpty {
            if store.searchText.isEmpty {
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
                Table(store.filteredProjects, selection: $store.selectedProjectName) {
                    TableColumn(String(localized: "Name", bundle: .l10n)) { project in
                        Text(verbatim: project.name).fontWeight(.medium)
                    }
                    TableColumn(String(localized: "Status", bundle: .l10n)) { project in
                        ComposeStatusBadge(status: project.status)
                    }
                    .width(min: 110, ideal: 130, max: 160)
                    TableColumn(String(localized: "Services", bundle: .l10n)) { project in
                        Text(verbatim: "\(project.services.count)").monospacedDigit()
                    }
                    .width(min: 60, ideal: 80, max: 100)
                    TableColumn(String(localized: "Working Directory", bundle: .l10n)) { project in
                        Text(verbatim: project.workingDir)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .contextMenu(forSelectionType: String.self) { names in
                    if let name = names.first, let project = store.projects.first(where: { $0.name == name }) {
                        Button {
                            Task { await store.up(project: project) }
                        } label: {
                            Text("Start stack", bundle: .l10n)
                        }
                        .disabled(!canAct)
                        Button(role: .destructive) {
                            askDown(project)
                        } label: {
                            Text("Stop stack", bundle: .l10n)
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
                }
                .frame(minHeight: 140)

                Group {
                    if let selected = store.selected {
                        detail(selected)
                    } else {
                        Text("Select a compose project", bundle: .l10n).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 160, maxHeight: .infinity)
            }
        }
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
                Text(verbatim: project.workingDir).font(.caption).foregroundStyle(.secondary)
                ForEach(project.configFiles, id: \.self) { file in
                    Text(verbatim: file).font(.caption.monospaced()).foregroundStyle(.secondary)
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
                        .foregroundStyle(.secondary)
                }
                .width(min: 100, ideal: 120, max: 140)
                TableColumn(String(localized: "State", bundle: .l10n)) { service in
                    HStack(spacing: 6) {
                        StatusDot(kind: service.statusKind ?? .stopped)
                        Text(verbatim: service.state ?? "-").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
    }
}

private struct ComposeStatusBadge: View {
    let status: ComposeStatus

    var body: some View {
        label
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.18))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private var label: some View {
        switch status {
        case .running: Text("Running", bundle: .l10n)
        case .partiallyRunning: Text("Partially running", bundle: .l10n)
        case .stopped: Text("Stopped", bundle: .l10n)
        case .down: Text("Down", bundle: .l10n)
        }
    }

    private var color: Color {
        switch status {
        case .running: .green
        case .partiallyRunning: .yellow
        case .stopped: .secondary
        case .down: .blue
        }
    }
}
