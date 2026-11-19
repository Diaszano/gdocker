import Foundation

public enum PermissionStoreError: Error, Equatable { case unknownTool(String) }

/// Per-tool Allow/Ask/Deny rules, persisted as JSON. Anything missing, unreadable or unknown falls back to the
/// catalog default, and an unknown tool name is always denied.
public actor PermissionStore {
    private let fileURL: URL
    private let catalog: [ToolSpec]
    private var overrides: [String: Permission]
    private var subscribers: [UUID: AsyncStream<Void>.Continuation] = [:]

    public init(fileURL: URL, catalog: [ToolSpec] = ToolCatalog.all) {
        self.fileURL = fileURL
        self.catalog = catalog
        let known = Set(catalog.map(\.name))
        let stored =
            (try? Data(contentsOf: fileURL))
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        overrides = stored.reduce(into: [:]) { result, entry in
            if known.contains(entry.key), let permission = Permission(rawValue: entry.value) {
                result[entry.key] = permission
            }
        }
    }

    public func permission(for tool: String) -> Permission {
        if let override = overrides[tool] { return override }
        return catalog.first { $0.name == tool }?.defaultPermission ?? .deny
    }

    public func set(_ permission: Permission, for tool: String) throws {
        guard catalog.contains(where: { $0.name == tool }) else { throw PermissionStoreError.unknownTool(tool) }
        overrides[tool] = permission
        try persist()
        subscribers.values.forEach { $0.yield() }
    }

    public func snapshot() -> [String: Permission] {
        Dictionary(uniqueKeysWithValues: catalog.map { ($0.name, permission(for: $0.name)) })
    }

    public func changes() -> AsyncStream<Void> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in Task { await self?.unsubscribe(id) } }
        return stream
    }

    private func unsubscribe(_ id: UUID) { subscribers[id] = nil }

    private func persist() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let raw = overrides.mapValues(\.rawValue)
        try JSONEncoder.sorted.encode(raw).write(to: fileURL, options: .atomic)
    }
}

extension JSONEncoder {
    fileprivate static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
