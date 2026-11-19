import Foundation

public struct ActivityEntry: Codable, Identifiable, Sendable, Equatable {
    public enum Outcome: String, Codable, Sendable { case allowed, approved, denied, error }

    public let id: UUID
    public let date: Date
    public let client: String
    public let tool: String
    public let arguments: String
    public let outcome: Outcome
    public let detail: String?
}

/// What the AI did through MCP, persisted as JSON lines. Only the newest `limit` entries are kept.
public actor ActivityLog {
    private let fileURL: URL
    private let limit: Int
    private var stored: [ActivityEntry] = []
    private var linesOnDisk = 0
    private var subscribers: [UUID: AsyncStream<Void>.Continuation] = [:]

    public init(fileURL: URL, limit: Int = 1000) {
        self.fileURL = fileURL
        self.limit = limit
        let decoder = Self.decoder
        let text = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        let lines = text.split(separator: "\n")
        linesOnDisk = lines.count
        // A corrupt line (for example from a crash mid-write) is skipped, not fatal.
        let entries = lines.compactMap { try? decoder.decode(ActivityEntry.self, from: Data($0.utf8)) }
        stored = Array(entries.suffix(limit))
    }

    public func record(client: String, tool: String, arguments: String, outcome: ActivityEntry.Outcome, detail: String?)
    {
        let entry = ActivityEntry(
            id: UUID(), date: Date(), client: client, tool: tool, arguments: arguments, outcome: outcome, detail: detail
        )
        stored.append(entry)
        if stored.count > limit { stored.removeFirst(stored.count - limit) }
        persist(appending: entry)
        subscribers.values.forEach { $0.yield() }
    }

    /// Newest first.
    public func entries() -> [ActivityEntry] { stored.reversed() }

    public func changes() -> AsyncStream<Void> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in Task { await self?.unsubscribe(id) } }
        return stream
    }

    private func unsubscribe(_ id: UUID) { subscribers[id] = nil }

    private func persist(appending entry: ActivityEntry) {
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if linesOnDisk + 1 > limit + 100 {
            rewrite()
            return
        }
        guard var line = try? Self.encoder.encode(entry) else { return }
        line.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: fileURL)
        }
        linesOnDisk += 1
    }

    /// Rewrites the file with only the kept entries, so it cannot grow without bound.
    private func rewrite() {
        var data = Data()
        for entry in stored {
            if let line = try? Self.encoder.encode(entry) {
                data.append(line)
                data.append(0x0A)
            }
        }
        try? data.write(to: fileURL, options: .atomic)
        linesOnDisk = stored.count
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}
