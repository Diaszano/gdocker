import AppKit
import GDockerCore
import SwiftUI

struct PermissionsView: View {
    let mcp: McpController

    private var model: PermissionsModel { mcp.permissionsModel }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Permissions", bundle: .l10n)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.ctp.text)
                    Text("Choose what each MCP client can do in your Docker", bundle: .l10n)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.ctp.muted)
                }

                ServerCard(mcp: mcp)
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 20)

            tableHeader
            Divider().overlay(Color.ctp.muted.opacity(0.18))

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.rows) { row in
                        ToolRow(row: row) { model.set($0, for: row.id) }
                        Divider().overlay(Color.ctp.muted.opacity(0.1))
                    }
                }
            }
        }
        .background(Color.ctp.bg)
    }

    private var tableHeader: some View {
        HStack(spacing: 16) {
            Text("Tool", bundle: .l10n).frame(width: 170, alignment: .leading)
            Text("Description", bundle: .l10n).frame(maxWidth: .infinity, alignment: .leading)
            Text("Risk", bundle: .l10n).frame(width: 100, alignment: .leading)
            Text("Permission", bundle: .l10n).frame(width: 224, alignment: .leading)
        }
        .textCase(.uppercase)
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(Color.ctp.muted)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color.ctp.side.opacity(0.6))
    }
}

private struct ToolRow: View {
    let row: PermissionsModel.Row
    let onChange: (Permission) -> Void

    var body: some View {
        HStack(spacing: 16) {
            Text(verbatim: row.spec.name)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.ctp.text)
                .lineLimit(1)
                .frame(width: 170, alignment: .leading)

            Text(LocalizedStringKey(row.spec.title), bundle: .l10n)
                .font(.system(size: 12))
                .foregroundStyle(Color.ctp.muted)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            StatusBadge(color: riskColor, label: LocalizedStringKey(riskLabel))
                .frame(width: 100, alignment: .leading)

            PermissionPicker(selection: row.permission, onChange: onChange)
                .frame(width: 224, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var riskLabel: String {
        switch row.spec.group {
        case .read: String(localized: "Low", bundle: .l10n)
        case .sensitiveRead, .control: String(localized: "Medium", bundle: .l10n)
        case .destructive: String(localized: "High", bundle: .l10n)
        }
    }

    private var riskColor: Color {
        switch row.spec.group {
        case .read: Color.ctp.ok
        case .sensitiveRead, .control: Color.ctp.warn
        case .destructive: Color.ctp.err
        }
    }
}

/// Allow / Ask / Deny segmented pill matching Penpot `03`.
private struct PermissionPicker: View {
    let selection: Permission
    let onChange: (Permission) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Permission.allCases, id: \.self) { option in
                Button {
                    onChange(option)
                } label: {
                    Text(option.title, bundle: .l10n)
                        .font(.system(size: 11, weight: option == selection ? .semibold : .regular))
                        .foregroundStyle(option == selection ? option.color : Color.ctp.muted)
                        .frame(width: 72, height: 22)
                        .background {
                            if option == selection {
                                RoundedRectangle(cornerRadius: 5).fill(option.color.opacity(0.18))
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(option == selection ? .isSelected : [])
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.ctp.side)
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.ctp.muted.opacity(0.24), lineWidth: 1))
        )
    }
}

extension Permission {
    fileprivate var title: LocalizedStringKey {
        switch self {
        case .allow: "Allow"
        case .ask: "Ask"
        case .deny: "Deny"
        }
    }

    fileprivate var color: Color {
        switch self {
        case .allow: Color.ctp.ok
        case .ask: Color.ctp.warn
        case .deny: Color.ctp.err
        }
    }
}

private struct ServerCard: View {
    let mcp: McpController

    @State private var copied = false
    @State private var confirmRegenerate = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Circle().fill(color).frame(width: 8, height: 8)
            title
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.ctp.text)
            Text(verbatim: detail)
                .font(.system(size: 12))
                .foregroundStyle(Color.ctp.muted)

            if !mcp.approvalModel.pending.isEmpty {
                Button {
                    mcp.showApprovals()
                } label: {
                    StatusBadge(
                        color: Color.ctp.warn,
                        label: LocalizedStringKey(
                            String(
                                localized: "\(String(mcp.approvalModel.pending.count)) awaiting approval", bundle: .l10n
                            ))
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if copied {
                Text("Copied", bundle: .l10n)
                    .font(.caption)
                    .foregroundStyle(Color.ctp.ok)
            }

            SectionMenuButton {
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
                Divider()
                Button {
                    confirmRegenerate = true
                } label: {
                    Text("Regenerate token", bundle: .l10n)
                }
                switch mcp.state {
                case .running:
                    Button {
                        Task { await mcp.stop() }
                    } label: {
                        Text("Stop", bundle: .l10n)
                    }
                case .stopped, .failed:
                    Button {
                        Task { await mcp.start() }
                    } label: {
                        Text("Start", bundle: .l10n)
                    }
                case .starting:
                    EmptyView()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.ctp.side.opacity(0.55))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.ctp.muted.opacity(0.24), lineWidth: 1))
        )
        .confirmationDialog(
            Text("Regenerate token?", bundle: .l10n), isPresented: $confirmRegenerate, titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                Task { await mcp.regenerateToken() }
            } label: {
                Text("Regenerate token", bundle: .l10n)
            }
            Button(role: .cancel) {
            } label: {
                Text("Cancel", bundle: .l10n)
            }
        } message: {
            Text("Clients using the old token stop working until you copy the config again.", bundle: .l10n)
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
            String(localized: "localhost:\(String(port)) · \(String(mcp.clientCount)) client(s)", bundle: .l10n)
        case .starting, .stopped: "localhost:\(McpController.configuredPort)"
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
