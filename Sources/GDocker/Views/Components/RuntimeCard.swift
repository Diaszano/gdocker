import GDockerCore
import SwiftUI

/// Bottom-of-sidebar runtime summary card, matching Penpot `01` (expanded) and `01d` (compact).
struct RuntimeCard: View {
    let connected: Bool
    let runningCount: Int
    let totalCount: Int
    let hostInfo: DockerHostInfo?
    let compact: Bool

    private var runtimeTitle: String {
        hostInfo?.isColima == true ? "Colima" : "Docker"
    }

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
                        Text(verbatim: runtimeTitle)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.ctp.text)
                    }
                    Spacer()
                    Text(connected ? "Running" : "Stopped", bundle: .l10n)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.ctp.muted)
                }

                HStack {
                    Text("Running", bundle: .l10n)
                    Spacer()
                    Text(verbatim: "\(runningCount)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.ctp.text)
                }
                .font(.system(size: 11))
                .foregroundStyle(Color.ctp.muted)

                if let cpus = hostInfo?.cpus, cpus > 0 {
                    let cpuPct = hostInfo?.cpuPercent ?? 0
                    let maxPct = Double(cpus) * 100.0
                    let normRatio = maxPct > 0 ? CGFloat(cpuPct / maxPct) : 0
                    let displayPct = Int(min(100, (cpuPct / Double(cpus)).rounded()))
                    metricBar(
                        label: Text(verbatim: "CPUs"),
                        value: "\(displayPct)% · \(cpus)",
                        ratio: normRatio,
                        color: Color.ctp.warn
                    )
                }

                if let memTotal = hostInfo?.memTotal, memTotal > 0 {
                    let used = hostInfo?.memUsed ?? 0
                    metricBar(
                        label: Text("Memory", bundle: .l10n),
                        value: "\(formatGB(used)) / \(formatGB(memTotal))",
                        ratio: CGFloat(used) / CGFloat(memTotal),
                        color: Color.ctp.accent
                    )
                }

                if let diskTotal = hostInfo?.diskTotal, diskTotal > 0 {
                    let used = hostInfo?.diskUsed ?? 0
                    metricBar(
                        label: Text("Disk", bundle: .l10n),
                        value: "\(formatGB(used)) / \(formatGB(diskTotal))",
                        ratio: CGFloat(used) / CGFloat(diskTotal),
                        color: Color.ctp.ok
                    )
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.ctp.bg.opacity(0.55))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.ctp.muted.opacity(0.22), lineWidth: 1))
            )
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
    }

    private func metricBar(label: Text, value: String, ratio: CGFloat, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                label
                    .font(.system(size: 10))
                    .foregroundStyle(Color.ctp.muted)
                Spacer()
                Text(verbatim: value)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.ctp.text)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.ctp.hover)
                    Capsule()
                        .fill(connected ? color : Color.ctp.err)
                        .frame(width: max(0, geo.size.width * min(1, max(0.05, ratio))))
                }
            }
            .frame(height: 4)
        }
    }

    private func formatGB(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824.0
        return String(format: "%.1f GB", gb)
    }
}
