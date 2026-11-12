import GDockerCore
import Observation

@MainActor @Observable
final class LogsModel {
    private(set) var buffer = LogBuffer()
    var filter = ""
    var follow = true
    var showTimestamps = false

    private var task: Task<Void, Never>?
    private var generation = 0
    private var pending: [LogLine] = []
    private var source: (client: DockerClient, id: String, tty: Bool)?

    var visibleLines: [LogLine] {
        guard !filter.isEmpty else { return buffer.lines }
        return buffer.lines.filter { $0.text.localizedCaseInsensitiveContains(filter) }
    }

    /// Starts streaming a container's logs, cancelling any previous stream.
    func attach(client: DockerClient, id: String, tty: Bool) {
        source = (client, id, tty)
        restart()
    }

    /// Re-opens the stream with the current options (used when "timestamps" changes).
    func restart() {
        task?.cancel()
        generation += 1
        buffer = LogBuffer()
        guard let source else { return }
        let current = generation
        let timestamps = showTimestamps
        pending = []
        task = Task {
            // Publishing every batch re-renders up to 5000 rows per batch; a chatty container pegs the CPU.
            // Collect lines and publish at most 4 times a second instead.
            // shortcut: SwiftUI re-diffs all rows (cost grows with the 5000-line cap); an NSTextView-backed log view
            // would avoid that if sustained firehose containers matter
            let flusher = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(250))
                    flush(generation: current)
                }
            }
            defer { flusher.cancel() }
            do {
                for try await batch in await source.client.logs(
                    source.id, tty: source.tty, follow: true, timestamps: timestamps
                ) {
                    // A cancelled stream may still deliver one batch; drop it so it can't land in the new buffer.
                    guard current == generation else { return }
                    pending += batch
                }
                flush(generation: current)
            } catch {
                // The stream ends with an error when the container goes away; the list view handles that.
            }
        }
    }

    func detach() {
        task?.cancel()
        task = nil
        source = nil
    }

    private func flush(generation current: Int) {
        guard current == generation, !pending.isEmpty else { return }
        buffer.append(pending)
        pending = []
    }
}
