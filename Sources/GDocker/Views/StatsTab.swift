import GDockerCore
import SwiftUI

struct StatsTab: View {
    let client: DockerClient?
    let id: String
    @State private var sample: StatsSample?

    var body: some View {
        Form {
            LabeledContent {
                Text(verbatim: cpu)
            } label: {
                Text("CPU", bundle: .l10n)
            }
            LabeledContent {
                Text(verbatim: memory)
            } label: {
                Text("Memory", bundle: .l10n)
            }
            LabeledContent {
                Text(verbatim: network)
            } label: {
                Text("Network", bundle: .l10n)
            }
        }
        .formStyle(.grouped)
        .task(id: id) {
            sample = nil
            guard let client else { return }
            do {
                for try await next in await client.stats(id) { sample = next }
            } catch {
                // The stream ends with an error when the container stops; keep the last sample.
            }
        }
    }

    private var cpu: String { sample.map { String(format: "%.1f%%", $0.cpuPercent) } ?? "—" }

    private var memory: String {
        guard let sample else { return "—" }
        return "\(bytes(sample.memoryUsed)) / \(bytes(sample.memoryLimit))"
    }

    private var network: String {
        guard let sample else { return "—" }
        return "↓ \(bytes(sample.netRx))  ↑ \(bytes(sample.netTx))"
    }

    private func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .memory)
    }
}
