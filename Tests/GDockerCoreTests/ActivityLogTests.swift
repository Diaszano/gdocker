import Foundation
import Testing

@testable import GDockerCore

private func tempFile() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("gdocker-\(UUID().uuidString)")
        .appendingPathComponent("activity.jsonl")
}

private func record(_ log: ActivityLog, _ tool: String, _ outcome: ActivityEntry.Outcome = .allowed) async {
    await log.record(client: "claude", tool: tool, arguments: "container=web", outcome: outcome, detail: nil)
}

@Test func activityRoundTripsAcrossInstances() async {
    let url = tempFile()
    let first = ActivityLog(fileURL: url)
    await first.record(
        client: "claude", tool: "stop_container", arguments: "container=web",
        outcome: .approved, detail: "ok")
    let entries = await ActivityLog(fileURL: url).entries()
    #expect(entries.count == 1)
    #expect(entries[0].client == "claude")
    #expect(entries[0].tool == "stop_container")
    #expect(entries[0].arguments == "container=web")
    #expect(entries[0].outcome == .approved)
    #expect(entries[0].detail == "ok")
}

@Test func activityEntriesAreNewestFirst() async {
    let log = ActivityLog(fileURL: tempFile())
    await record(log, "t1")
    await record(log, "t2")
    #expect(await log.entries().map(\.tool) == ["t2", "t1"])
}

@Test func activityKeepsNewestWithinLimit() async {
    let url = tempFile()
    let log = ActivityLog(fileURL: url, limit: 3)
    for n in 1...5 { await record(log, "t\(n)") }
    #expect(await log.entries().map(\.tool) == ["t5", "t4", "t3"])
    #expect(await ActivityLog(fileURL: url, limit: 3).entries().map(\.tool) == ["t5", "t4", "t3"])
}

@Test func activitySkipsCorruptLines() async throws {
    let url = tempFile()
    let log = ActivityLog(fileURL: url)
    await record(log, "t1")
    await record(log, "t2")
    var lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
    lines.insert("{ this is not json", at: 1)
    try lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
    #expect(await ActivityLog(fileURL: url).entries().map(\.tool) == ["t2", "t1"])
}

@Test func activityFileIsTrimmedWhenFarOverTheLimit() async throws {
    let url = tempFile()
    let log = ActivityLog(fileURL: url, limit: 2)
    for n in 1...150 { await record(log, "t\(n)") }
    let lineCount = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").count
    #expect(lineCount <= 2 + 100 + 1)
}

@Test func activityChangesEmitsOnRecord() async {
    let log = ActivityLog(fileURL: tempFile())
    var changes = await log.changes().makeAsyncIterator()
    await record(log, "t1")
    #expect(await changes.next() != nil)
}
