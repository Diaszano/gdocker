import SwiftUI

struct EnvTab: View {
    let env: [String]

    var body: some View {
        if env.isEmpty {
            Text("No environment variables", bundle: .l10n).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(env, id: \.self) { entry in
                let parts = entry.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                HStack(alignment: .top) {
                    Text(verbatim: String(parts[0])).fontWeight(.semibold).frame(width: 220, alignment: .leading)
                    Text(verbatim: parts.count > 1 ? String(parts[1]) : "").foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
            }
        }
    }
}
