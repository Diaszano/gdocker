import AppKit
import GDockerCore
import SwiftUI

/// Menu bar status item label showing the GDocker box icon and live active/approval indicators.
struct MenuBarIconLabel: View {
    let store: ContainersStore
    let mcp: McpController
    let compact: Bool

    private var runningCount: Int {
        store.all.filter { $0.statusKind == .running }.count
    }

    private var pendingCount: Int {
        mcp.approvalModel.pending.count
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: pendingCount > 0 ? "shippingbox.fill" : "shippingbox")
            if !compact {
                if !store.connected {
                    Text(verbatim: "!")
                } else if pendingCount > 0 {
                    Text(verbatim: "\(runningCount) !")
                } else {
                    Text(verbatim: "\(runningCount)")
                }
            }
        }
        .font(.system(size: 12, weight: .medium, design: .monospaced))
    }
}

/// Compact 3-column CPU, memory, and disk summary card shown at the top of the menu bar popover.
struct MenuBarRuntimeSummaryCard: View {
    let connected: Bool
    let runningCount: Int
    let stoppedCount: Int
    let hostInfo: DockerHostInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Host resources", bundle: .l10n)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.ctp.muted)
                Spacer()
                Text(
                    verbatim: String(
                        localized: "\(String(runningCount)) active · \(String(stoppedCount)) stopped", bundle: .l10n)
                )
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.ctp.text)
            }

            HStack(spacing: 12) {
                cpuColumn
                memoryColumn
                diskColumn
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.ctp.side)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.ctp.muted.opacity(0.22), lineWidth: 1))
        )
    }

    @ViewBuilder private var cpuColumn: some View {
        let cpus = max(1, hostInfo?.cpus ?? 0)
        let rawPct = hostInfo?.cpuPercent ?? 0
        let pct = hostInfo?.cpus ?? 0 > 0 ? Int(min(100, (rawPct / Double(cpus)).rounded())) : 0
        let ratio = hostInfo?.cpus ?? 0 > 0 ? CGFloat(rawPct / (Double(cpus) * 100.0)) : 0
        metricColumn(label: Text(verbatim: "CPU"), value: "\(pct)%", ratio: ratio, color: Color.ctp.warn)
    }

    @ViewBuilder private var memoryColumn: some View {
        let total = hostInfo?.memTotal ?? 0
        let used = hostInfo?.memUsed ?? 0
        let ratio = total > 0 ? CGFloat(used) / CGFloat(total) : 0
        let value = total > 0 ? "\(formatGB(used)) / \(formatGB(total))" : "—"
        metricColumn(label: Text("Memory", bundle: .l10n), value: value, ratio: ratio, color: Color.ctp.accent)
    }

    @ViewBuilder private var diskColumn: some View {
        let total = hostInfo?.diskTotal ?? 0
        let used = hostInfo?.diskUsed ?? 0
        let ratio = total > 0 ? CGFloat(used) / CGFloat(total) : 0
        let value = total > 0 ? "\(formatGB(used)) / \(formatGB(total))" : "—"
        metricColumn(label: Text("Disk", bundle: .l10n), value: value, ratio: ratio, color: Color.ctp.ok)
    }

    private func metricColumn(label: Text, value: String, ratio: CGFloat, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            label
                .font(.system(size: 10))
                .foregroundStyle(Color.ctp.muted)
            Text(verbatim: value)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.ctp.text)
                .lineLimit(1)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.ctp.hover)
                    Capsule()
                        .fill(connected ? color : Color.ctp.err)
                        .frame(width: max(4, geo.size.width * min(1, max(0.04, ratio))))
                }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formatGB(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824.0
        return gb >= 10 ? String(format: "%.0f GB", gb) : String(format: "%.1f GB", gb)
    }
}

/// Inline pending MCP approval banner allowing the user to Deny or Allow without leaving the popover.
struct MenuBarApprovalBanner: View {
    let request: ApprovalRequest
    let pendingCount: Int
    let answer: (ApprovalDecision) -> Void

    private var commandSummary: String {
        let base: String
        if request.arguments.isEmpty {
            base = request.tool
        } else {
            let args = request.arguments.map { "\($0.name): \($0.value)" }.joined(separator: " · ")
            base = "\(request.tool) (\(args))"
        }
        if let reason = request.reason, !reason.isEmpty {
            return "\(base) — \(reason)"
        }
        return base
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.ctp.warn)
                Text("AI approval pending", bundle: .l10n)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.ctp.warn)
                Spacer()
                Text(verbatim: pendingCount > 1 ? "\(request.client) (1/\(pendingCount))" : request.client)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.ctp.text)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.ctp.hover))
            }

            Text(verbatim: commandSummary)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Color.ctp.text)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.ctp.code))

            HStack(spacing: 6) {
                Button {
                    answer(.deny)
                } label: {
                    Text("Deny", bundle: .l10n)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.ctp.err)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.ctp.hover)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6).strokeBorder(
                                        Color.ctp.err.opacity(0.45), lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)

                if request.allowsAlways {
                    Button {
                        answer(.allowAlways)
                    } label: {
                        Text("Allow always", bundle: .l10n)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.ctp.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.ctp.accent.opacity(0.16))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6).strokeBorder(
                                            Color.ctp.accent.opacity(0.5), lineWidth: 1))
                            )
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    answer(.allowOnce)
                } label: {
                    Text("Allow once", bundle: .l10n)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.ctp.code)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.ctp.ok))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.ctp.warn.opacity(0.1))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.ctp.warn.opacity(0.55), lineWidth: 1))
        )
    }
}

/// Collapsible Compose stack header with service health count and quick Up/Restart/Stop actions.
struct MenuBarComposeHeader: View {
    let title: String
    let runningCount: Int
    let totalCount: Int
    let isExpanded: Bool
    let hasComposeProject: Bool
    let canUp: Bool
    let onToggle: () -> Void
    let onUp: (() -> Void)?
    let onRestart: (() -> Void)?
    let onStop: (() -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onToggle) {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.ctp.muted)
                        .frame(width: 10)
                    Image(systemName: "square.stack.3d.forward.dottedline")
                        .font(.system(size: 12))
                        .foregroundStyle(hasComposeProject ? Color.ctp.accent : Color.ctp.muted)
                    Text(verbatim: title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Color.ctp.text)
                        .lineLimit(1)
                    if totalCount > 0 {
                        Text(verbatim: "\(runningCount)/\(totalCount)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(runningCount == totalCount ? Color.ctp.ok : Color.ctp.muted)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(
                                    (runningCount == totalCount ? Color.ctp.ok : Color.ctp.muted).opacity(0.14))
                            )
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 4) {
                if canUp, let onUp {
                    IconActionButton(systemImage: "play.fill", tint: Color.ctp.ok, size: 22, help: "Up", action: onUp)
                }
                if runningCount > 0, let onRestart {
                    IconActionButton(
                        systemImage: "arrow.clockwise", tint: Color.ctp.muted, size: 22, help: "Restart",
                        action: onRestart)
                }
                if runningCount > 0, let onStop {
                    IconActionButton(
                        systemImage: "stop.fill", tint: Color.ctp.err, size: 22, help: "Stop", action: onStop)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.ctp.side)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.ctp.muted.opacity(0.18), lineWidth: 1))
        )
    }
}

/// Compact container row for the menu bar popover with brand logo, clickable ports, and quick actions.
struct MenuBarContainerRow: View {
    let container: ContainerSummary
    let isConfirmingRemove: Bool
    let onAction: (ContainerAction) -> Void
    let onRequestRemove: () -> Void
    let onCancelRemove: () -> Void
    let onOpenTab: (DetailTabRequest) -> Void

    @State private var hovered = false

    private var uniquePublicPorts: [Int] {
        var seen = Set<Int>()
        return container.ports.compactMap { binding in
            guard let pub = binding.publicPort, seen.insert(pub).inserted else { return nil }
            return pub
        }
        .sorted()
    }

    var body: some View {
        HStack(spacing: 8) {
            ServiceLogo(image: container.image, size: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(verbatim: container.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.ctp.text)
                        .lineLimit(1)
                    StatusDot(kind: container.statusKind)
                }

                HStack(spacing: 5) {
                    if !uniquePublicPorts.isEmpty && container.isActive {
                        ForEach(uniquePublicPorts.prefix(2), id: \.self) { port in
                            Button {
                                if let url = URL(string: "http://localhost:\(port)") {
                                    NSWorkspace.shared.open(url)
                                }
                            } label: {
                                Text(verbatim: ":\(port) ↗")
                                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color.ctp.accent)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.ctp.accent.opacity(0.14))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 4)
                                                    .strokeBorder(Color.ctp.accent.opacity(0.35), lineWidth: 0.75)
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text(verbatim: subtitleText)
                        .font(.system(size: 10.5))
                        .foregroundStyle(container.statusKind == .failed ? Color.ctp.err : Color.ctp.muted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if isConfirmingRemove {
                HStack(spacing: 4) {
                    Button(action: onCancelRemove) {
                        Text("Cancel", bundle: .l10n)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Color.ctp.muted)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 5).fill(Color.ctp.side))
                    }
                    .buttonStyle(.plain)

                    Button {
                        onAction(.remove)
                    } label: {
                        Text("Remove", bundle: .l10n)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(Color.ctp.code)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 5).fill(Color.ctp.err))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                HStack(spacing: 4) {
                    IconActionButton(systemImage: "doc.text", tint: Color.ctp.muted, size: 24, help: "Logs") {
                        onOpenTab(.logs)
                    }
                    if container.isActive {
                        IconActionButton(systemImage: "terminal", tint: Color.ctp.muted, size: 24, help: "Terminal") {
                            onOpenTab(.terminal)
                        }
                        IconActionButton(
                            systemImage: "arrow.clockwise", tint: Color.ctp.muted, size: 24, help: "Restart"
                        ) {
                            onAction(.restart)
                        }
                        IconActionButton(systemImage: "stop.fill", tint: Color.ctp.err, size: 24, help: "Stop") {
                            onAction(.stop)
                        }
                    } else {
                        IconActionButton(systemImage: "play.fill", tint: Color.ctp.ok, size: 24, help: "Start") {
                            onAction(.start)
                        }
                        IconActionButton(
                            systemImage: "trash", tint: Color.ctp.err, size: 24, help: "Remove", action: onRequestRemove
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(hovered ? Color.ctp.hover.opacity(0.6) : Color.clear)
        )
        .onHover { hovered = $0 }
        .contextMenu {
            Button {
                onOpenTab(.logs)
            } label: {
                Text("Logs", bundle: .l10n)
            }
            if container.isActive {
                Button {
                    onOpenTab(.terminal)
                } label: {
                    Text("Terminal", bundle: .l10n)
                }
                Divider()
                Button {
                    onAction(.restart)
                } label: {
                    Text("Restart", bundle: .l10n)
                }
                Button {
                    onAction(.stop)
                } label: {
                    Text("Stop", bundle: .l10n)
                }
            } else {
                Button {
                    onAction(.start)
                } label: {
                    Text("Start", bundle: .l10n)
                }
                Divider()
                Button(role: .destructive, action: onRequestRemove) { Text("Remove", bundle: .l10n) }
            }
        }
    }

    private var subtitleText: String {
        if container.isActive {
            if let sizeRw = container.sizeRw {
                return ByteCountFormatter.string(fromByteCount: sizeRw, countStyle: .file)
            }
            return container.status
        }
        return container.status
    }
}

/// Bottom MCP server strip inside the popover with live status, Copy config menu, and On/Off toggle.
struct MenuBarMcpStrip: View {
    let mcp: McpController
    @State private var copied = false

    private var isRunning: Bool {
        if case .running = mcp.state { return true }
        return false
    }

    private var statusColor: Color {
        switch mcp.state {
        case .running: Color.ctp.ok
        case .starting, .stopped: Color.ctp.muted
        case .failed: Color.ctp.err
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "server.rack")
                .font(.system(size: 13))
                .foregroundStyle(Color.ctp.accent)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text("MCP server", bundle: .l10n)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color.ctp.text)
                HStack(spacing: 5) {
                    Circle().fill(statusColor).frame(width: 6, height: 6)
                    subtitleView
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                }
            }

            Spacer()

            if copied {
                Text("Copied", bundle: .l10n)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color.ctp.ok)
            } else {
                Menu {
                    Button {
                        copy(.claudeCodeHTTP)
                    } label: {
                        Text("Claude Code (HTTP)", bundle: .l10n)
                    }
                    Button {
                        copy(.jsonHTTP)
                    } label: {
                        Text("JSON (HTTP)", bundle: .l10n)
                    }
                    Button {
                        copy(.claudeDesktopStdio)
                    } label: {
                        Text("Claude Desktop (stdio)", bundle: .l10n)
                    }
                } label: {
                    Text("Copy config", bundle: .l10n)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Color.ctp.text)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.ctp.hover)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6).strokeBorder(
                                        Color.ctp.muted.opacity(0.25), lineWidth: 1))
                        )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            Toggle(
                "",
                isOn: Binding(
                    get: { isRunning },
                    set: { shouldRun in
                        Task {
                            if shouldRun { await mcp.start() } else { await mcp.stop() }
                        }
                    }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.ctp.side)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.ctp.muted.opacity(0.22), lineWidth: 1))
        )
    }

    @ViewBuilder private var subtitleView: some View {
        switch mcp.state {
        case .running(let port):
            Text(verbatim: String(localized: ":\(String(port)) · \(String(mcp.clientCount)) client(s)", bundle: .l10n))
        case .starting:
            Text("Starting MCP server…", bundle: .l10n)
        case .stopped:
            Text("MCP server stopped", bundle: .l10n)
        case .failed(let msg):
            Text(verbatim: msg)
        }
    }

    private func copy(_ kind: ConfigKind) {
        Task {
            let snippet = await mcp.configSnippet(kind)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(snippet, forType: .string)
            copied = true
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }
}
