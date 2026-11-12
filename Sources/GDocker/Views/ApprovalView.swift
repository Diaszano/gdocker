import GDockerCore
import SwiftUI

struct ApprovalView: View {
    let model: ApprovalModel

    var body: some View {
        Group {
            if let request = model.current {
                RequestCard(request: request, pendingCount: model.pending.count) { model.answer($0) }
                    // A new request starts with "always allow" unchecked.
                    .id(request.id)
            } else {
                Color.clear.frame(width: 440, height: 1)
            }
        }
    }
}

private struct RequestCard: View {
    let request: ApprovalRequest
    let pendingCount: Int
    let answer: (ApprovalDecision) -> Void
    @State private var always = false

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 26))
                .foregroundStyle(.orange)
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.15)))
            Text(verbatim: title).font(.headline).multilineTextAlignment(.center)
            if pendingCount > 1 {
                Text(verbatim: String(localized: "\(String(1)) of \(String(pendingCount))", bundle: .l10n))
                    .font(.caption).foregroundStyle(.secondary)
            }
            details
            if request.allowsAlways {
                Toggle(isOn: $always) { Text("Always allow this action", bundle: .l10n) }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                // No keyboard shortcuts on purpose: see ApprovalPanelController. The user must click.
                Button { answer(.deny) } label: { Text("Deny", bundle: .l10n).frame(maxWidth: .infinity) }
                Button { answer(always ? .allowAlways : .allowOnce) } label: {
                    (always ? Text("Allow always", bundle: .l10n) : Text("Allow once", bundle: .l10n))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
        }
        .padding(24)
        .frame(width: 440)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: request.tool).fontWeight(.semibold)
            ForEach(request.arguments, id: \.name) { argument in
                Text(verbatim: "\(argument.name): \(argument.value)")
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
            if let reason = request.reason, !reason.isEmpty {
                Divider().padding(.vertical, 2)
                Text("Reason", bundle: .l10n).font(.caption).foregroundStyle(.secondary)
                Text(verbatim: reason).lineLimit(4)
            }
        }
        .font(.system(size: 12, design: .monospaced))
        .textSelection(.enabled)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.12)))
    }

    private var title: String {
        let action = ToolCatalog.spec(named: request.tool).map {
            Bundle.l10n.localizedString(forKey: $0.title, value: nil, table: nil)
        } ?? request.tool
        return String(localized: "\(request.client) wants to run: \(action)", bundle: .l10n)
    }
}
