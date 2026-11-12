import Foundation

public struct LogLine: Identifiable, Sendable, Hashable {
    public enum Stream: Sendable, Hashable { case stdout, stderr }

    public let id: Int
    public let stream: Stream
    public let timestamp: Date?
    public let text: String

    public init(id: Int, stream: Stream, timestamp: Date?, text: String) {
        self.id = id; self.stream = stream; self.timestamp = timestamp; self.text = text
    }
}

/// Decodes Docker's log stream into lines. Without a TTY the stream is multiplexed in frames
/// (`[stream, 0, 0, 0, size UInt32 big-endian] + payload`); with a TTY it is raw stdout.
/// Frames and lines may be split across `feed` calls, so partial data is kept between calls.
public struct LogDemuxer {
    private let tty: Bool
    private let timestamps: Bool
    private var raw: [UInt8] = []
    private var partial: [LogLine.Stream: [UInt8]] = [:]
    private var nextID = 1
    private let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    public init(tty: Bool, timestamps: Bool) {
        self.tty = tty
        self.timestamps = timestamps
    }

    public mutating func feed(_ bytes: [UInt8]) -> [LogLine] {
        var lines: [LogLine] = []
        if tty {
            append(bytes, .stdout, to: &lines)
            return lines
        }
        raw += bytes
        while raw.count >= 8 {
            let size = Int(raw[4]) << 24 | Int(raw[5]) << 16 | Int(raw[6]) << 8 | Int(raw[7])
            guard raw.count >= 8 + size else { break }
            let stream: LogLine.Stream = raw[0] == 2 ? .stderr : .stdout
            let payload = Array(raw[8..<(8 + size)])
            raw.removeFirst(8 + size)
            append(payload, stream, to: &lines)
        }
        return lines
    }

    /// Emits a trailing line that never got its newline, for when the stream ends.
    public mutating func flush() -> [LogLine] {
        var lines: [LogLine] = []
        for stream in [LogLine.Stream.stdout, .stderr] {
            if let rest = partial[stream], !rest.isEmpty { lines.append(makeLine(rest, stream)) }
        }
        partial = [:]
        return lines
    }

    private mutating func append(_ payload: [UInt8], _ stream: LogLine.Stream, to lines: inout [LogLine]) {
        var buffer = partial[stream, default: []] + payload
        while let newline = buffer.firstIndex(of: 0x0A) {
            var bytes = Array(buffer[..<newline])
            buffer.removeSubrange(...newline)
            if bytes.last == 0x0D { bytes.removeLast() }
            lines.append(makeLine(bytes, stream))
        }
        partial[stream] = buffer
    }

    private mutating func makeLine(_ bytes: [UInt8], _ stream: LogLine.Stream) -> LogLine {
        var text = String(decoding: bytes, as: UTF8.self)
        var date: Date?
        if timestamps, let space = text.firstIndex(of: " "),
           let parsed = formatter.date(from: String(text[..<space])) {
            date = parsed
            text = String(text[text.index(after: space)...])
        }
        defer { nextID += 1 }
        return LogLine(id: nextID, stream: stream, timestamp: date, text: text)
    }
}

/// Keeps only the newest `limit` lines so a chatty container cannot grow memory without bound.
public struct LogBuffer: Sendable {
    public let limit: Int
    public private(set) var lines: [LogLine] = []

    public init(limit: Int = 5000) { self.limit = limit }

    public mutating func append(_ newLines: [LogLine]) {
        lines += newLines
        if lines.count > limit { lines.removeFirst(lines.count - limit) }
    }
}
