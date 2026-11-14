import GDockerCore
import SwiftUI

struct ActivityView: View {
    let model: ActivityModel
    let approvalModel: ApprovalModel

    private var callsToday: Int {
        let cal = Calendar.current
        return model.entries.filter { cal.isDateInToday($0.date) }.count
    }

    private var allowedCount: Int {
        model.entries.filter { $0.outcome == .allowed || $0.outcome == .approved }.count
    }

    private var deniedCount: Int {
        model.entries.filter { $0.outcome == .denied }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI activity", bundle: .l10n)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.ctp.text)
                    Text("Calls made by MCP clients to your Docker, in real time", bundle: .l10n)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.ctp.muted)
                }

                HStack(spacing: 12) {
                    KpiCard(title: String(localized: "Calls today", bundle: .l10n), value: callsToday)
                    KpiCard(title: String(localized: "Allowed", bundle: .l10n), value: allowedCount)
                    KpiCard(title: String(localized: "Denied", bundle: .l10n), value: deniedCount)
                    KpiCard(title: String(localized: "Pending", bundle: .l10n), value: approvalModel.pending.count)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 20)

            tableHeader
            Divider().overlay(Color.ctp.muted.opacity(0.18))

            if model.entries.isEmpty {
                Text("No AI activity yet", bundle: .l10n)
                    .foregroundStyle(Color.ctp.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.entries) { entry in
                            EntryRow(entry: entry)
                            Divider().overlay(Color.ctp.muted.opacity(0.1))
                        }
                    }
                }
            }
        }
        .background(Color.ctp.bg)
    }

    private var tableHeader: some View {
        HStack(spacing: 12) {
            Text("Time", bundle: .l10n).frame(width: 72, alignment: .leading)
            Text("Tool", bundle: .l10n).frame(width: 150, alignment: .leading)
            Text("Target", bundle: .l10n).frame(width: 170, alignment: .leading)
            Text("Client", bundle: .l10n).frame(width: 120, alignment: .leading)
            Text("Outcome", bundle: .l10n).frame(width: 112, alignment: .leading)
            Text("Detail", bundle: .l10n).frame(maxWidth: .infinity, alignment: .leading)
        }
        .textCase(.uppercase)
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(Color.ctp.muted)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color.ctp.side.opacity(0.6))
    }
}

private struct KpiCard: View {
    let title: String
    let value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: title)
                .font(.system(size: 11))
                .foregroundStyle(Color.ctp.muted)
            Text(verbatim: "\(value)")
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.ctp.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.ctp.side.opacity(0.5))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.ctp.muted.opacity(0.24), lineWidth: 1))
        )
    }
}

private struct EntryRow: View {
    let entry: ActivityEntry

    var body: some View {
        HStack(spacing: 12) {
            Text(entry.date.formatted(.dateTime.hour().minute().second()))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.ctp.muted)
                .frame(width: 72, alignment: .leading)

            Text(verbatim: entry.tool)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.ctp.text)
                .lineLimit(1)
                .frame(width: 150, alignment: .leading)

            Text(verbatim: entry.arguments.isEmpty ? "—" : entry.arguments)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.ctp.muted)
                .lineLimit(1)
                .frame(width: 170, alignment: .leading)

            Text(verbatim: entry.client)
                .font(.system(size: 12))
                .foregroundStyle(Color.ctp.muted)
                .lineLimit(1)
                .frame(width: 120, alignment: .leading)

            StatusBadge(color: outcomeColor, label: outcomeLabel)
                .frame(width: 112, alignment: .leading)

            Text(verbatim: entry.detail ?? "—")
                .font(.system(size: 12))
                .foregroundStyle(Color.ctp.muted)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var outcomeLabel: LocalizedStringKey {
        switch entry.outcome {
        case .allowed: "Allowed"
        case .approved: "Approved"
        case .denied: "Denied"
        case .error: "Error"
        }
    }

    private var outcomeColor: Color {
        switch entry.outcome {
        case .allowed: Color.ctp.ok
        case .approved: Color.ctp.accent
        case .denied: Color.ctp.err
        case .error: Color.ctp.warn
        }
    }
}
