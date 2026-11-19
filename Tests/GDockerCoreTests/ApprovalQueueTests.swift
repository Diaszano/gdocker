import Foundation
import Testing

@testable import GDockerCore

private func request(_ tool: String = "stop_container") -> ApprovalRequest {
    ApprovalRequest(client: "c", tool: tool, arguments: [], reason: nil, allowsAlways: true)
}

/// Polls until the queue holds `count` pending requests, so a test can act only after `decide` has enqueued.
private func waitForPending(_ queue: ApprovalQueue, count: Int) async throws {
    for _ in 0..<400 {
        if await queue.pending().count == count { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("queue never reached \(count) pending requests")
}

@Test func decideReturnsResolvedDecision() async throws {
    let queue = ApprovalQueue()
    let r = request()
    let task = Task { await queue.decide(r) }
    try await waitForPending(queue, count: 1)
    await queue.resolve(r.id, .allowOnce)
    #expect(await task.value == .allowOnce)
    #expect(await queue.pending().isEmpty)
}

@Test func pendingIsFIFOAndResolvingTheMiddleKeepsTheRest() async throws {
    let queue = ApprovalQueue()
    let (a, b, c) = (request("a"), request("b"), request("c"))
    let ta = Task { await queue.decide(a) }
    try await waitForPending(queue, count: 1)
    let tb = Task { await queue.decide(b) }
    try await waitForPending(queue, count: 2)
    let tc = Task { await queue.decide(c) }
    try await waitForPending(queue, count: 3)
    #expect(await queue.pending().map(\.id) == [a.id, b.id, c.id])

    await queue.resolve(b.id, .deny)
    #expect(await tb.value == .deny)
    #expect(await queue.pending().map(\.id) == [a.id, c.id])

    await queue.resolve(a.id, .allowAlways)
    await queue.resolve(c.id, .allowOnce)
    #expect(await ta.value == .allowAlways)
    #expect(await tc.value == .allowOnce)
}

@Test func resolvingUnknownOrTwiceIsANoOp() async throws {
    let queue = ApprovalQueue()
    await queue.resolve(UUID(), .allowOnce)
    let r = request()
    let task = Task { await queue.decide(r) }
    try await waitForPending(queue, count: 1)
    await queue.resolve(r.id, .deny)
    await queue.resolve(r.id, .allowOnce)
    #expect(await task.value == .deny)
}

@Test func cancellingDecideRemovesPendingAndReturnsDeny() async throws {
    let queue = ApprovalQueue()
    let task = Task { await queue.decide(request()) }
    try await waitForPending(queue, count: 1)
    task.cancel()
    #expect(await task.value == .deny)
    try await waitForPending(queue, count: 0)
}

@Test func decideOnAnAlreadyCancelledTaskDoesNotHang() async {
    let queue = ApprovalQueue()
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return await queue.decide(request())
    }
    #expect(await task.value == .deny)
    #expect(await queue.pending().isEmpty)
}

@Test func changesEmitsPendingLists() async throws {
    let queue = ApprovalQueue()
    var changes = await queue.changes().makeAsyncIterator()
    let r = request()
    let task = Task { await queue.decide(r) }
    #expect(await changes.next()?.map(\.id) == [r.id])
    await queue.resolve(r.id, .allowOnce)
    #expect(await changes.next()?.isEmpty == true)
    _ = await task.value
}
