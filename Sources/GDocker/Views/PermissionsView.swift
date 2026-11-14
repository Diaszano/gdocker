import AppKit
import GDockerCore
import SwiftUI

struct PermissionsView: View {
    let mcp: McpController

    private var model: PermissionsModel { mcp.permissionsModel }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ServerCard(mcp: mcp)
                Text("Choose what the AI can do on its own, what needs your approval, and what is forbidden.", bundle: .l10n)
                    .font(.callout)
                    .foregroundStyle(Color.ctp.muted)
                ForEach(ToolGroup.allCases, id: \.self) { group in
                    let rows = model.rows(in: group)
                    if !rows.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(group.title, bundle: .l10n)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.ctp.muted)
                                .textCase(.uppercase)
                                .padding(.bottom, 6)
                            ForEach(rows) { row in
                                ToolRow(row: row) { model.set($0, for: row.id) }
                                if row.id != rows.last?.id { Divider() }
                            }
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(Text("Permissions", bundle: .l10n))
    }
}

private extension ToolGroup {
    var title: LocalizedStringKey {
        switch self {
        case .read: "Reading"
        case .sensitiveRead: "Sensitive reading"
        case .control: "Control"
        case .destructive: "Destructive"
        }
    }
}

// MARK: - A tool and its rule

private struct ToolRow: View {
    let row: PermissionsModel.Row
    let onChange: (Permission) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(row.spec.title), bundle: .l10n).fontWeight(.medium)
                Text(verbatim: row.spec.name)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            PermissionPicker(selection: row.permission, onChange: onChange)
        }
        .padding(.vertical, 10)
    }
}

/// Allow / Ask / Deny. A custom control rather than a segmented `Picker`, so the selected option can wear its color
/// (green, orange, red) as in the design.
private struct PermissionPicker: View {
    let selection: Permission
    let onChange: (Permission) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Permission.allCases, id: \.self) { option in
                Button { onChange(option) } label: {
                    Text(option.title, bundle: .l10n)
                        .font(.system(size: 11, weight: option == selection ? .semibold : .regular))
                        .foregroundStyle(option == selection ? option.color : Color.ctp.muted)
                        .frame(width: 72, height: 22)
                        .background {
                            if option == selection {
                                RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .controlBackgroundColor))
                                    .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(option == selection ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.ctp.muted.opacity(0.15)))
    }
}

private extension Permission {
    var title: LocalizedStringKey {
        switch self {
        case .allow: "Allow"
        case .ask: "Ask"
        case .deny: "Deny"
        }
    }

    var color: Color {
        switch self {
        case .allow: Color.ctp.ok
        case .ask: Color.ctp.warn
        case .deny: Color.ctp.err
        }
    }
}

// MARK: - The server

private struct ServerCard: View {
    let mcp: McpController
    @State private var copied = false
    @State private var confirmRegenerate = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Circle().fill(color).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 3) {
                title.fontWeight(.semibold)
                Text(verbatim: detail).font(.caption).foregroundStyle(Color.ctp.muted)
            }
            Spacer()
            if copied { Text("Copied", bundle: .l10n).font(.caption).foregroundStyle(Color.ctp.ok) }
            Menu {
                Button { copy(.claudeCodeHTTP) } label: { Text("Claude Code (HTTP)", bundle: .l10n) }
                Button { copy(.jsonHTTP) } label: { Text("JSON (HTTP)", bundle: .l10n) }
                Button { copy(.claudeDesktopStdio) } label: { Text("Claude Desktop (stdio)", bundle: .l10n) }
            } label: { Text("Copy config", bundle: .l10n) }
            .fixedSize()
            Button { confirmRegenerate = true } label: { Text("Regenerate token", bundle: .l10n) }
            toggleButton
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.ctp.muted.opacity(0.1)))
        .confirmationDialog(
            Text("Regenerate token?", bundle: .l10n), isPresented: $confirmRegenerate, titleVisibility: .visible
        ) {
            Button(role: .destructive) { Task { await mcp.regenerateToken() } } label: {
                Text("Regenerate token", bundle: .l10n)
            }
            Button(role: .cancel) {} label: { Text("Cancel", bundle: .l10n) }
        } message: {
            Text("Clients using the old token stop working until you copy the config again.", bundle: .l10n)
        }
    }

    @ViewBuilder private var toggleButton: some View {
        switch mcp.state {
        case .running:
            Button { Task { await mcp.stop() } } label: { Text("Stop", bundle: .l10n) }
        case .starting:
            ProgressView().controlSize(.small)
        case .stopped, .failed:
            Button { Task { await mcp.start() } } label: { Text("Start", bundle: .l10n) }
        }
    }

    private var color: Color {
        switch mcp.state {
        case .running: Color.ctp.ok
        case .starting, .stopped: Color.ctp.muted
        case .failed: Color.ctp.err
        }
    }

    @ViewBuilder private var title: some View {
        switch mcp.state {
        case .running: Text("MCP server active", bundle: .l10n)
        case .starting: Text("Starting MCP server…", bundle: .l10n)
        case .stopped: Text("MCP server stopped", bundle: .l10n)
        case .failed: Text("MCP server error", bundle: .l10n)
        }
    }

    private var detail: String {
        switch mcp.state {
        case .running(let port):
            "http://localhost:\(port)/mcp  ·  " + String(localized: "Connected clients: \(String(mcp.clientCount))", bundle: .l10n)
        case .starting, .stopped: "http://localhost:\(McpController.configuredPort)/mcp"
        case .failed(let message): message
        }
    }

    private func copy(_ kind: ConfigKind) {
        Task {
            let text = await mcp.configSnippet(kind)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }
}
