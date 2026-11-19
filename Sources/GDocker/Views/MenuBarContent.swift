import AppKit
import GDockerCore
import SwiftUI

private enum MenuBarFilter: CaseIterable {
    case running, stopped, compose, all
}

/// Catppuccin-themed macOS menu bar popover shown when keeping GDocker running with the main window closed.
struct MenuBarContent: View {
    @Environment(ContainersStore.self) private var store
    @Environment(ComposeStore.self) private var composeStore
    @Environment(McpController.self) private var mcp
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @AppStorage(SettingsKey.theme) private var theme = Theme.system

    @State private var filter: MenuBarFilter = .running
    @State private var searchText = ""
    @State private var collapsedGroups: Set<String> = []
    @State private var confirmPruneStopped = false
    @State private var confirmRemoveID: String?
    @State private var showRecentActivity = false
    @State private var isRefreshing = false

    private var runningCount: Int {
        store.all.filter { $0.statusKind == .running || $0.statusKind == .transitioning }.count
    }

    private var stoppedContainers: [ContainerSummary] {
        store.all.filter { $0.statusKind == .stopped || $0.statusKind == .failed }
    }

    private var stoppedCount: Int { stoppedContainers.count }

    private var runtimeTitle: String {
        store.hostInfo?.isColima == true ? "Colima" : "Docker"
    }

    private var filteredContainers: [ContainerSummary] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return store.all.filter { container in
            switch filter {
            case .running:
                guard container.statusKind == .running || container.statusKind == .transitioning else { return false }
            case .stopped:
                guard container.statusKind == .stopped || container.statusKind == .failed else { return false }
            case .compose:
                guard container.composeProject != nil else { return false }
            case .all:
                break
            }
            guard !query.isEmpty else { return true }
            return container.name.localizedCaseInsensitiveContains(query)
                || container.image.localizedCaseInsensitiveContains(query)
                || (container.composeProject?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var visibleGroups: [ContainerGroup] {
        groupByCompose(filteredContainers)
    }

    private var visibleComposeProjects: [ComposeProject] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return composeStore.projects.filter { project in
            if filter == .stopped && project.status != .stopped && project.status != .down {
                return false
            }
            return project.matches(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.ctp.muted.opacity(0.18))

            VStack(spacing: 10) {
                if let request = mcp.approvalModel.current {
                    MenuBarApprovalBanner(request: request, pendingCount: mcp.approvalModel.pending.count) { decision in
                        mcp.approvalModel.answer(decision)
                    }
                }

                if let errorText = store.lastError ?? composeStore.lastError {
                    errorBanner(errorText)
                }

                if store.connected {
                    MenuBarRuntimeSummaryCard(
                        connected: store.connected,
                        runningCount: runningCount,
                        stoppedCount: stoppedCount,
                        hostInfo: store.hostInfo
                    )
                } else {
                    disconnectedCard
                }

                searchField
                filterRow

                if filter == .stopped && stoppedCount > 0 {
                    pruneStoppedBar
                }

                listSection
                recentActivityToggle
                MenuBarMcpStrip(mcp: mcp)
            }
            .padding(12)

            footer
        }
        .frame(width: 406)
        .background(Color.ctp.bg)
        .tint(Color.ctp.accent)
        .id(theme)
        .task {
            store.start()
            await mcp.startIfEnabled()
            await composeStore.refresh()
        }
        .onChange(of: store.revision) { _, _ in
            Task { await composeStore.refresh() }
        }
        .onChange(of: store.all.count) { _, _ in
            Task { await composeStore.refresh() }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.ctp.accent)
                .frame(width: 24, height: 24)
                .overlay {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.ctp.bg)
                }

            Text(verbatim: "GDocker")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.ctp.text)

            HStack(spacing: 5) {
                Circle()
                    .fill(store.connected ? Color.ctp.ok : Color.ctp.err)
                    .frame(width: 6, height: 6)
                Text(verbatim: store.connected ? runtimeTitle : String(localized: "Stopped", bundle: .l10n))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(store.connected ? Color.ctp.ok : Color.ctp.err)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill((store.connected ? Color.ctp.ok : Color.ctp.err).opacity(0.14))
                    .overlay(
                        Capsule().strokeBorder(
                            (store.connected ? Color.ctp.ok : Color.ctp.err).opacity(0.4),
                            lineWidth: 1
                        )
                    )
            )

            Spacer()

            IconActionButton(systemImage: "arrow.clockwise", tint: Color.ctp.muted, size: 26, help: "Refresh") {
                refreshNow()
            }
            .disabled(isRefreshing)

            IconActionButton(systemImage: "trash", tint: Color.ctp.err, size: 26, help: "Clean Stopped") {
                filter = .stopped
                confirmPruneStopped = stoppedCount > 0
            }
            .disabled(!store.connected || stoppedCount == 0)

            Button {
                openMainWindow()
            } label: {
                HStack(spacing: 4) {
                    Text("Open", bundle: .l10n)
                        .font(.system(size: 11, weight: .semibold))
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Color.ctp.accent)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.ctp.accent.opacity(0.16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6).strokeBorder(Color.ctp.accent.opacity(0.45), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Search & Filters

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Color.ctp.muted)
            TextField(
                "", text: $searchText,
                prompt: Text("Search containers or stacks...", bundle: .l10n).foregroundStyle(Color.ctp.muted)
            )
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(Color.ctp.text)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.ctp.muted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.ctp.code)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.ctp.muted.opacity(0.25), lineWidth: 1))
        )
    }

    private var filterRow: some View {
        HStack(spacing: 6) {
            filterChip(.running, title: "Running", count: runningCount, dot: Color.ctp.ok)
            filterChip(.stopped, title: "Stopped", count: stoppedCount, dot: Color.ctp.muted)
            filterChip(.compose, title: "Compose", count: composeStore.count, dot: nil)
            filterChip(.all, title: "All", count: store.all.count, dot: nil)
            Spacer()
        }
    }

    private func filterChip(_ item: MenuBarFilter, title: LocalizedStringKey, count: Int, dot: Color?) -> some View {
        let selected = filter == item
        return Button {
            filter = item
            confirmPruneStopped = false
        } label: {
            HStack(spacing: 5) {
                if let dot {
                    Circle().fill(dot).frame(width: 5.5, height: 5.5)
                }
                Text(title, bundle: .l10n)
                    .font(.system(size: 11, weight: selected ? .semibold : .medium))
                Text(verbatim: "\(count)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(selected ? Color.ctp.accent : Color.ctp.muted)
            }
            .foregroundStyle(selected ? Color.ctp.text : Color.ctp.muted)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(selected ? Color.ctp.accent.opacity(0.16) : Color.ctp.side)
                    .overlay(
                        Capsule().strokeBorder(
                            selected ? Color.ctp.accent : Color.ctp.muted.opacity(0.25),
                            lineWidth: 1
                        )
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Prune & Banners

    private var pruneStoppedBar: some View {
        HStack(spacing: 8) {
            Text(verbatim: String(localized: "\(String(stoppedCount)) stopped containers", bundle: .l10n))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.ctp.muted)
            Spacer()
            if confirmPruneStopped {
                Button {
                    confirmPruneStopped = false
                } label: {
                    Text("Cancel", bundle: .l10n)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Color.ctp.muted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.ctp.hover))
                }
                .buttonStyle(.plain)

                Button {
                    confirmPruneStopped = false
                    Task {
                        _ = await store.pruneStopped()
                        await composeStore.refresh()
                    }
                } label: {
                    Text("Confirm", bundle: .l10n)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Color.ctp.code)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.ctp.err))
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    confirmPruneStopped = true
                } label: {
                    Text("Clean Stopped", bundle: .l10n)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.ctp.err)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.ctp.err.opacity(0.14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6).strokeBorder(
                                        Color.ctp.err.opacity(0.4), lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.ctp.side)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.ctp.muted.opacity(0.22), lineWidth: 1))
        )
    }

    private var disconnectedCard: some View {
        HStack(spacing: 8) {
            Circle().fill(Color.ctp.err).frame(width: 7, height: 7)
            Text("Docker disconnected", bundle: .l10n)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.ctp.text)
            Spacer()
            Button {
                refreshNow()
            } label: {
                Text("Refresh", bundle: .l10n)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.ctp.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.ctp.accent.opacity(0.16)))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.ctp.err.opacity(0.1))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.ctp.err.opacity(0.35), lineWidth: 1))
        )
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Color.ctp.err)
            Text(verbatim: message)
                .font(.system(size: 10.5))
                .foregroundStyle(Color.ctp.text)
                .lineLimit(2)
            Spacer()
            Button {
                store.lastError = nil
                composeStore.lastError = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.ctp.muted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.ctp.err.opacity(0.14))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.ctp.err.opacity(0.45), lineWidth: 1))
        )
    }

    // MARK: - Container & Compose List

    private var stoppedComposeProjects: [ComposeProject] {
        composeStore.projects.filter { $0.status == .down }
    }

    private var estimatedListHeight: CGFloat {
        let headerH: CGFloat = 34
        let rowH: CGFloat = 46
        let gap: CGFloat = 6
        let raw: CGFloat
        if filter == .compose {
            if visibleComposeProjects.isEmpty { return 64 }
            raw = visibleComposeProjects.reduce(0) { acc, project in
                let collapsed = collapsedGroups.contains(project.name)
                let count = collapsed ? 0 : store.all.filter { $0.composeProject == project.name }.count
                return acc + headerH + gap + CGFloat(count) * (rowH + gap)
            }
        } else if visibleGroups.isEmpty && (filter != .stopped || stoppedComposeProjects.isEmpty) {
            return 64
        } else {
            let groupsH = visibleGroups.reduce(CGFloat(0)) { acc, group in
                let key = group.project ?? "__ungrouped__"
                let collapsed = collapsedGroups.contains(key)
                let titleH: CGFloat = group.project != nil ? headerH : 22
                let count = collapsed ? 0 : group.containers.count
                return acc + titleH + gap + CGFloat(count) * (rowH + gap)
            }
            let downH = filter == .stopped ? CGFloat(stoppedComposeProjects.count) * 58 : 0
            raw = groupsH + downH
        }
        return min(310, max(64, raw))
    }

    private var listSection: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                if filter == .compose {
                    composeOnlyList
                } else {
                    groupedContainerList
                    if filter == .stopped {
                        stoppedComposeSection
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .frame(height: estimatedListHeight)
    }

    @ViewBuilder private var groupedContainerList: some View {
        if visibleGroups.isEmpty {
            emptyStateView
        } else {
            ForEach(visibleGroups) { group in
                let key = group.project ?? "__ungrouped__"
                let isCollapsed = collapsedGroups.contains(key)
                if let projectName = group.project {
                    let project = composeStore.projects.first { $0.name == projectName }
                    let projectRunning = group.containers.filter { $0.statusKind == .running }.count
                    let ids = Set(group.containers.map(\.id))
                    MenuBarComposeHeader(
                        title: projectName,
                        runningCount: projectRunning,
                        totalCount: group.containers.count,
                        isExpanded: !isCollapsed,
                        hasComposeProject: true,
                        canUp: project != nil && projectRunning < group.containers.count,
                        onToggle: { toggleGroup(key) },
                        onUp: project.map { p in { Task { await composeStore.up(project: p) } } },
                        onRestart: { Task { await store.performBulk(.restart, on: ids) } },
                        onStop: { Task { await store.performBulk(.stop, on: ids) } }
                    )
                } else {
                    HStack {
                        Text("No group", bundle: .l10n)
                            .textCase(.uppercase)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.ctp.muted)
                        Spacer()
                    }
                    .padding(.horizontal, 6)
                    .padding(.top, visibleGroups.count > 1 ? 4 : 0)
                }

                if !isCollapsed {
                    ForEach(group.containers) { container in
                        MenuBarContainerRow(
                            container: container,
                            isConfirmingRemove: confirmRemoveID == container.id,
                            onAction: { action in
                                if action == .remove {
                                    confirmRemoveID = nil
                                }
                                Task { await store.perform(action, on: container.id) }
                            },
                            onRequestRemove: { confirmRemoveID = container.id },
                            onCancelRemove: { confirmRemoveID = nil },
                            onOpenTab: { tab in openContainer(container.id, tab: tab) }
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder private var composeOnlyList: some View {
        if visibleComposeProjects.isEmpty {
            Text("No Compose Projects", bundle: .l10n)
                .font(.system(size: 12))
                .foregroundStyle(Color.ctp.muted)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 24)
        } else {
            ForEach(visibleComposeProjects) { project in
                let isCollapsed = collapsedGroups.contains(project.name)
                let containers = store.all.filter { $0.composeProject == project.name }.sorted { $0.name < $1.name }
                let ids = Set(containers.map(\.id))
                let runningInProject = project.services.filter { $0.statusKind == .running }.count
                let totalInProject = project.services.count
                MenuBarComposeHeader(
                    title: project.name,
                    runningCount: runningInProject,
                    totalCount: totalInProject,
                    isExpanded: !isCollapsed,
                    hasComposeProject: true,
                    canUp: project.status != .running,
                    onToggle: { toggleGroup(project.name) },
                    onUp: { Task { await composeStore.up(project: project) } },
                    onRestart: ids.isEmpty ? nil : { Task { await store.performBulk(.restart, on: ids) } },
                    onStop: runningInProject == 0
                        ? nil
                        : {
                            if !ids.isEmpty {
                                Task { await store.performBulk(.stop, on: ids) }
                            } else {
                                Task { await composeStore.down(project: project) }
                            }
                        }
                )
                if !isCollapsed {
                    ForEach(containers) { container in
                        MenuBarContainerRow(
                            container: container,
                            isConfirmingRemove: confirmRemoveID == container.id,
                            onAction: { action in
                                if action == .remove { confirmRemoveID = nil }
                                Task { await store.perform(action, on: container.id) }
                            },
                            onRequestRemove: { confirmRemoveID = container.id },
                            onCancelRemove: { confirmRemoveID = nil },
                            onOpenTab: { tab in openContainer(container.id, tab: tab) }
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder private var stoppedComposeSection: some View {
        let downProjects = stoppedComposeProjects
        if !downProjects.isEmpty {
            Text("Compose", bundle: .l10n)
                .textCase(.uppercase)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.ctp.muted)
                .padding(.horizontal, 6)
                .padding(.top, 4)

            ForEach(downProjects) { project in
                let runningInProject = project.services.filter { $0.statusKind == .running }.count
                let totalInProject = project.services.count
                HStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.forward.dottedline")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.ctp.muted)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: project.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.ctp.text)
                        Text(
                            verbatim: String(
                                localized: "\(String(runningInProject)) of \(String(totalInProject)) running",
                                bundle: .l10n)
                        )
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.ctp.muted)
                    }
                    Spacer()
                    Button {
                        Task { await composeStore.up(project: project) }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 10))
                            Text("Up", bundle: .l10n)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(Color.ctp.ok)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.ctp.ok.opacity(0.14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6).strokeBorder(
                                        Color.ctp.ok.opacity(0.45), lineWidth: 1))
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.ctp.side)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8).strokeBorder(Color.ctp.muted.opacity(0.2), lineWidth: 1))
                )
            }
        }
    }

    @ViewBuilder private var emptyStateView: some View {
        Group {
            if !searchText.isEmpty {
                Text("No matching containers", bundle: .l10n)
            } else if filter == .running {
                Text("No containers running", bundle: .l10n)
            } else if filter == .stopped {
                Text("No stopped containers", bundle: .l10n)
            } else {
                Text("No matching containers", bundle: .l10n)
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(Color.ctp.muted)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 22)
    }

    // MARK: - Recent AI Activity

    @ViewBuilder private var recentActivityToggle: some View {
        let entries = Array(mcp.activityModel.entries.prefix(3))
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    showRecentActivity.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: showRecentActivity ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.ctp.muted)
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.ctp.accent)
                        Text("Recent AI activity", bundle: .l10n)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.ctp.muted)
                        Spacer()
                        Text(verbatim: "\(mcp.activityModel.entries.count)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color.ctp.muted)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showRecentActivity {
                    VStack(spacing: 4) {
                        ForEach(entries) { entry in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(outcomeColor(entry.outcome))
                                    .frame(width: 5.5, height: 5.5)
                                Text(verbatim: entry.tool)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(Color.ctp.text)
                                    .lineLimit(1)
                                Spacer()
                                Text(entry.date, style: .time)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(Color.ctp.muted)
                            }
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.ctp.side)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8).strokeBorder(
                                    Color.ctp.muted.opacity(0.18), lineWidth: 1))
                    )
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            Divider().overlay(Color.ctp.muted.opacity(0.18))
            HStack {
                Button {
                    openMainWindow()
                } label: {
                    Text("Open window", bundle: .l10n)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Color.ctp.accent)
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    openSettingsWindow()
                } label: {
                    Text("Settings", bundle: .l10n)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.ctp.muted)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(",", modifiers: .command)

                Text(verbatim: "·")
                    .foregroundStyle(Color.ctp.muted.opacity(0.5))

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Text("Quit", bundle: .l10n)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.ctp.err)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("q", modifiers: .command)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.ctp.side)
        }
    }

    // MARK: - Actions

    private func toggleGroup(_ key: String) {
        if collapsedGroups.contains(key) {
            collapsedGroups.remove(key)
        } else {
            collapsedGroups.insert(key)
        }
    }

    private func refreshNow() {
        isRefreshing = true
        Task {
            defer { isRefreshing = false }
            await store.refresh()
            await composeStore.refresh()
        }
    }

    private func openContainer(_ id: String, tab: DetailTabRequest) {
        store.requestInspector(containerID: id, tab: tab)
        openMainWindow()
    }

    private func openMainWindow() {
        // The Dock icon was hidden while the window was closed; bring it back before showing the window.
        NSApp.setActivationPolicy(.regular)
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openSettingsWindow() {
        NSApp.setActivationPolicy(.regular)
        openSettings()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func outcomeColor(_ outcome: ActivityEntry.Outcome) -> Color {
        switch outcome {
        case .allowed, .approved: Color.ctp.ok
        case .denied: Color.ctp.warn
        case .error: Color.ctp.err
        }
    }
}
