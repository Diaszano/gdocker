import GDockerCore
import SwiftUI

struct ApprovalView: View {
    let model: ApprovalModel

    var body: some View {
        Group {
            if let request = model.current {
                RequestCard(request: request, pendingCount: model.pending.count) { model.answer($0) }
                    .id(request.id)
            } else {
                Color.clear.frame(width: 460, height: 1)
            }
        }
    }
}

private struct RequestCard: View {
    let request: ApprovalRequest
    let pendingCount: Int
    let answer: (ApprovalDecision) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerSection
            details
            actionsSection
        }
        .padding(22)
        .frame(width: 460)
        .background(Color.ctp.bg)
    }

    private var headerSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.ctp.warn)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.ctp.warn.opacity(0.16)))

            VStack(alignment: .leading, spacing: 2) {
                Text("Approve AI call?", bundle: .l10n)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.ctp.text)
                Text(
                    verbatim: String(localized: "\(request.client) wants to execute a sensitive action", bundle: .l10n)
                )
                .font(.system(size: 12))
                .foregroundStyle(Color.ctp.muted)
            }
            Spacer()
            if pendingCount > 1 {
                Text(verbatim: String(localized: "\(String(1)) of \(String(pendingCount))", bundle: .l10n))
                    .font(.caption)
                    .foregroundStyle(Color.ctp.muted)
            }
        }
    }

    private var actionsSection: some View {
        HStack(spacing: 10) {
            Spacer()
            // No keyboard shortcuts on purpose: see ApprovalPanelController. The user must click.
            Button {
                answer(.deny)
            } label: {
                Text("Deny", bundle: .l10n)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.ctp.err)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.ctp.err.opacity(0.14)))
            }
            .buttonStyle(.plain)

            Button {
                answer(.allowOnce)
            } label: {
                Text("Allow once", bundle: .l10n)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.ctp.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.ctp.hover))
            }
            .buttonStyle(.plain)

            if request.allowsAlways {
                Button {
                    answer(.allowAlways)
                } label: {
                    Text("Allow always", bundle: .l10n)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.ctp.bg)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.ctp.accent))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            detailRow(label: String(localized: "Tool", bundle: .l10n), value: request.tool)
            ForEach(request.arguments, id: \.name) { argument in
                detailRow(label: argument.name, value: argument.value)
            }
            if let reason = request.reason, !reason.isEmpty {
                detailRow(label: String(localized: "Reason", bundle: .l10n), value: reason)
            }
        }
        .textSelection(.enabled)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.ctp.side)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.ctp.muted.opacity(0.2), lineWidth: 1))
        )
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(verbatim: label)
                .font(.system(size: 12))
                .foregroundStyle(Color.ctp.muted)
                .frame(width: 82, alignment: .leading)
            Text(verbatim: value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.ctp.text)
                .lineLimit(4)
        }
    }
}
