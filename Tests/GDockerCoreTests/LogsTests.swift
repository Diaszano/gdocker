import Foundation
import Testing

@testable import GDockerCore

/// Docker multiplexed frame: [stream, 0, 0, 0, size (UInt32 big-endian)] + payload.
private func frame(_ stream: UInt8, _ payload: [UInt8]) -> [UInt8] {
    let n = UInt32(payload.count)
    return [stream, 0, 0, 0, UInt8(n >> 24), UInt8((n >> 16) & 0xFF), UInt8((n >> 8) & 0xFF), UInt8(n & 0xFF)] + payload
}

private func frame(_ stream: UInt8, _ text: String) -> [UInt8] { frame(stream, Array(text.utf8)) }

@Test func demuxTwoFrames() {
    var demuxer = LogDemuxer(tty: false, timestamps: false)
    let lines = demuxer.feed(frame(1, "hello\n") + frame(2, "oops\n"))
    #expect(lines.map(\.text) == ["hello", "oops"])
    #expect(lines.map(\.stream) == [.stdout, .stderr])
}

@Test func demuxSplitFrame() {
    let bytes = frame(1, "hello\n") + frame(2, "oops\n")
    var demuxer = LogDemuxer(tty: false, timestamps: false)
    var lines: [LogLine] = []
    lines += demuxer.feed(Array(bytes[0..<5]))
    lines += demuxer.feed(Array(bytes[5..<11]))
    lines += demuxer.feed(Array(bytes[11...]))
    #expect(lines.map(\.text) == ["hello", "oops"])
    #expect(lines.map(\.stream) == [.stdout, .stderr])
}

@Test func demuxPartialLineAcrossFrames() {
    var demuxer = LogDemuxer(tty: false, timestamps: false)
    var lines = demuxer.feed(frame(1, "ab"))
    #expect(lines.isEmpty)
    lines = demuxer.feed(frame(1, "c\n"))
    #expect(lines.map(\.text) == ["abc"])
}

@Test func invalidUTF8IsReplaced() {
    var demuxer = LogDemuxer(tty: false, timestamps: false)
    let lines = demuxer.feed(frame(1, [0x66, 0xFF, 0x0A]))
    #expect(lines.map(\.text) == ["f\u{FFFD}"])
}

@Test func ttyIsRawStdout() {
    var demuxer = LogDemuxer(tty: true, timestamps: false)
    let lines = demuxer.feed(Array("x\r\ny\n".utf8))
    #expect(lines.map(\.text) == ["x", "y"])
    #expect(lines.allSatisfy { $0.stream == .stdout })
}

@Test func timestampsAreParsedAndStripped() {
    var demuxer = LogDemuxer(tty: false, timestamps: true)
    let lines = demuxer.feed(frame(1, "2026-11-12T14:02:11.123456789Z Server up\n"))
    #expect(lines.map(\.text) == ["Server up"])
    #expect(lines.first?.timestamp != nil)
}

@Test func bufferKeepsOnlyTheNewestLines() {
    var buffer = LogBuffer(limit: 3)
    buffer.append((1...5).map { LogLine(id: $0, stream: .stdout, timestamp: nil, text: "l\($0)") })
    #expect(buffer.lines.map(\.id) == [3, 4, 5])
}
