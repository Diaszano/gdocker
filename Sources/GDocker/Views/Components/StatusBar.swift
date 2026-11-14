import GDockerCore
import SwiftUI

/// Bottom status bar across main views, matching Penpot `01`–`04`.
struct StatusBar: View {
    let connected: Bool
    let runningCount: Int
    let totalCount: Int
    let hostInfo: DockerHostInfo?
    let mcp: McpController

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Circle()
                    .fill(connected ? Color.ctp.ok : Color.ctp.err)
                    .frame(width: 6, height: 6)
                if hostInfo?.isColima == true {
                    if connected {
                        Text("Colima connected", bundle: .l10n)
                    } else {
                        Text("Docker disconnected", bundle: .l10n)
                    }
                } else {
                    if connected {
                        Text("Docker connected", bundle: .l10n)
                    } else {
                        Text("Docker disconnected", bundle: .l10n)
                    }
                }
            }

            Text(verbatim: String(localized: "\(String(runningCount)) of \(String(totalCount)) running", bundle: .l10n))
                .foregroundStyle(Color.ctp.muted)

            if let memTotal = hostInfo?.memTotal, memTotal > 0 {
                let gb = Double(memTotal) / 1_073_741_824.0
                Text(verbatim: String(format: "%.1f GB RAM", gb))
                    .foregroundStyle(Color.ctp.muted)
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(mcpDotColor)
                    .frame(width: 6, height: 6)
                Text(verbatim: mcpLabel)
            }

            if !mcp.approvalModel.pending.isEmpty {
                Button {
                    mcp.showApprovals()
                } label: {
                    StatusBadge(
                        color: Color.ctp.warn,
                        label: LocalizedStringKey(String(localized: "\(String(mcp.approvalModel.pending.count)) awaiting approval", bundle: .l10n))
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .font(.system(size: 11))
        .foregroundStyle(Color.ctp.muted)
        .padding(.horizontal, 16)
        .frame(height: 32)
        .background(Color.ctp.side)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.ctp.muted.opacity(0.18)).frame(height: 1)
        }
    }

    private var mcpDotColor: Color {
        switch mcp.state {
        case .running: Color.ctp.accent
        case .starting, .stopped: Color.ctp.muted
        case .failed: Color.ctp.err
        }
    }

    private var mcpLabel: String {
        switch mcp.state {
        case .running:
            String(localized: "MCP active · \(String(mcp.clientCount)) client(s)", bundle: .l10n)
        case .starting:
            String(localized: "Starting…", bundle: .l10n)
        case .stopped:
            String(localized: "Stopped", bundle: .l10n)
        case .failed(let msg):
            msg
        }
    }
}
