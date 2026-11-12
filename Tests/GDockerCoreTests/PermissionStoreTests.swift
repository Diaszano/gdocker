import Foundation
import Testing
@testable import GDockerCore

private func tempFile() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("gdocker-\(UUID().uuidString)")
        .appendingPathComponent("permissions.json")
}

@Test func unknownToolIsDenied() async {
    let store = PermissionStore(fileURL: tempFile())
    #expect(await store.permission(for: "nope") == .deny)
}

@Test func missingFileGivesDefaults() async {
    let store = PermissionStore(fileURL: tempFile())
    #expect(await store.permission(for: "list_containers") == .allow)
    #expect(await store.permission(for: "stop_container") == .ask)
    #expect(await store.snapshot().count == ToolCatalog.all.count)
}

@Test func setPersistsAcrossInstances() async throws {
    let url = tempFile()
    try await PermissionStore(fileURL: url).set(.allow, for: "stop_container")
    #expect(await PermissionStore(fileURL: url).permission(for: "stop_container") == .allow)
}

@Test func setOnUnknownToolThrows() async {
    let store = PermissionStore(fileURL: tempFile())
    await #expect(throws: PermissionStoreError.unknownTool("ghost")) { try await store.set(.allow, for: "ghost") }
}

@Test func corruptFileFallsBackToDefaultsAndIsRewritten() async throws {
    let url = tempFile()
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data([0xFF, 0x00, 0x13, 0x37]).write(to: url)
    let store = PermissionStore(fileURL: url)
    #expect(await store.permission(for: "stop_container") == .ask)
    try await store.set(.deny, for: "get_logs")
    #expect(await PermissionStore(fileURL: url).permission(for: "get_logs") == .deny)
}

@Test func unknownToolsAndBadValuesInFileAreIgnored() async throws {
    let url = tempFile()
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(#"{"ghost":"allow","stop_container":"maybe","get_logs":"deny"}"#.utf8).write(to: url)
    let store = PermissionStore(fileURL: url)
    let snapshot = await store.snapshot()
    #expect(snapshot["ghost"] == nil)
    #expect(snapshot["stop_container"] == .ask)
    #expect(snapshot["get_logs"] == .deny)
}

@Test func changesEmitsOnSet() async throws {
    let store = PermissionStore(fileURL: tempFile())
    var changes = await store.changes().makeAsyncIterator()
    try await store.set(.allow, for: "stop_container")
    #expect(await changes.next() != nil)
}
