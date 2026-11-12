import Foundation

public struct ApprovalArgument: Sendable, Equatable {
    public let name: String
    public let value: String

    public init(name: String, value: String) { self.name = name; self.value = value }
}

public struct ApprovalRequest: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let client: String
    public let tool: String
    public let arguments: [ApprovalArgument]
    public let reason: String?
    public let allowsAlways: Bool

    public init(client: String, tool: String, arguments: [ApprovalArgument], reason: String?, allowsAlways: Bool) {
        self.id = UUID()
        self.client = client; self.tool = tool; self.arguments = arguments
        self.reason = reason; self.allowsAlways = allowsAlways
    }
}

public enum ApprovalDecision: Sendable, Equatable { case allowOnce, allowAlways, deny }

public protocol ApprovalPrompter: Sendable {
    func decide(_ request: ApprovalRequest) async -> ApprovalDecision
}

/// First-in-first-out queue of approval requests waiting for the user. The UI watches `changes()` and answers
/// with `resolve`. A request whose caller is cancelled (for example by a timeout) leaves the queue as a denial.
public actor ApprovalQueue: ApprovalPrompter {
    private var queue: [ApprovalRequest] = []
    private var waiting: [UUID: CheckedContinuation<ApprovalDecision, Never>] = [:]
    private var subscribers: [UUID: AsyncStream<[ApprovalRequest]>.Continuation] = [:]

    public init() {}

    public func decide(_ request: ApprovalRequest) async -> ApprovalDecision {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                // Cancelled before we got here: onCancel already ran and found nothing to remove.
                if Task.isCancelled {
                    continuation.resume(returning: .deny)
                    return
                }
                queue.append(request)
                waiting[request.id] = continuation
                publish()
            }
        } onCancel: {
            Task { await self.finish(request.id, .deny) }
        }
    }

    public func resolve(_ id: UUID, _ decision: ApprovalDecision) { finish(id, decision) }

    public func pending() -> [ApprovalRequest] { queue }

    public func changes() -> AsyncStream<[ApprovalRequest]> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<[ApprovalRequest]>.makeStream()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in Task { await self?.unsubscribe(id) } }
        return stream
    }

    private func finish(_ id: UUID, _ decision: ApprovalDecision) {
        guard let continuation = waiting.removeValue(forKey: id) else { return }
        queue.removeAll { $0.id == id }
        continuation.resume(returning: decision)
        publish()
    }

    private func publish() { subscribers.values.forEach { $0.yield(queue) } }

    private func unsubscribe(_ id: UUID) { subscribers[id] = nil }
}
