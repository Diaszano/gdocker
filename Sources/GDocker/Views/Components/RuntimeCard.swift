import GDockerCore
import SwiftUI

/// Bottom-of-sidebar runtime summary card, matching Penpot `01` (expanded) and `01d` (compact).
struct RuntimeCard: View {
    let connected: Bool
    let runningCount: Int
    let totalCount: Int
    let compact: Bool

    var body: some View {
        if compact {
            VStack(spacing: 4) {
                Circle()
                    .fill(connected ? Color.ctp.ok : Color.ctp.err)
                    .frame(width: 8, height: 8)
                Text(verbatim: "\(runningCount)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.ctp.text)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.ctp.bg.opacity(0.65))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.ctp.muted.opacity(0.22), lineWidth: 1))
            )
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(connected ? Color.ctp.ok : Color.ctp.err)
                            .frame(width: 7, height: 7)
                        Text("Docker", bundle: .l10n)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.ctp.text)
                    }
                    Spacer()
                    Text(connected ? "Running" : "Stopped", bundle: .l10n)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.ctp.muted)
                }

                HStack {
                    Text(verbatim: String(localized: "\(String(runningCount)) of \(String(totalCount)) containers", bundle: .l10n))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.ctp.muted)
                    Spacer()
                }

                GeometryReader { geo in
                    let ratio = totalCount > 0 ? CGFloat(runningCount) / CGFloat(totalCount) : 0
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.ctp.hover)
                        Capsule()
                            .fill(connected ? Color.ctp.accent : Color.ctp.err)
                            .frame(width: max(0, geo.size.width * min(1, ratio)))
                    }
                }
                .frame(height: 4)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.ctp.bg.opacity(0.55))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.ctp.muted.opacity(0.22), lineWidth: 1))
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
    }
}
