import GDockerCore
import SwiftUI

struct ActivityView: View {
    let model: ActivityModel

    var body: some View {
        Group {
            if model.entries.isEmpty {
                Text("No AI activity yet", bundle: .l10n).foregroundStyle(Color.ctp.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.entries) { EntryRow(entry: $0) }
            }
        }
        .navigationTitle(Text("AI activity", bundle: .l10n))
    }
}

private struct EntryRow: View {
    let entry: ActivityEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            OutcomeBadge(outcome: entry.outcome)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(verbatim: entry.tool).font(.system(size: 12, weight: .semibold, design: .monospaced))
                    Text(verbatim: entry.client).foregroundStyle(Color.ctp.muted)
                }
                if !entry.arguments.isEmpty {
                    Text(verbatim: entry.arguments)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.ctp.muted)
                        .lineLimit(2)
                }
                if let detail = entry.detail {
                    Text(verbatim: detail).font(.caption).foregroundStyle(.tertiary).lineLimit(2)
                }
            }
            Spacer()
            Text(entry.date.formatted(date: .abbreviated, time: .standard))
                .font(.caption).foregroundStyle(Color.ctp.muted)
        }
        .padding(.vertical, 4)
    }
}

private struct OutcomeBadge: View {
    let outcome: ActivityEntry.Outcome

    var body: some View {
        label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 78, height: 20)
            .background(RoundedRectangle(cornerRadius: 5).fill(color.opacity(0.15)))
    }

    @ViewBuilder private var label: some View {
        switch outcome {
        case .allowed: Text("Allowed", bundle: .l10n)
        case .approved: Text("Approved", bundle: .l10n)
        case .denied: Text("Denied", bundle: .l10n)
        case .error: Text("Error", bundle: .l10n)
        }
    }

    private var color: Color {
        switch outcome {
        case .allowed: Color.ctp.ok
        case .approved: Color.ctp.accent
        case .denied: Color.ctp.err
        case .error: Color.ctp.warn
        }
    }
}
