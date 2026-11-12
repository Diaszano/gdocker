import GDockerCore
import Observation

/// The permission rules as the UI sees them, kept in sync with the store (the router also changes rules, when the
/// user picks "always allow" in an approval prompt).
@MainActor @Observable
final class PermissionsModel {
    struct Row: Identifiable {
        let spec: ToolSpec
        var permission: Permission
        var id: String { spec.id }
    }

    private(set) var rows: [Row] = []
    private let store: PermissionStore
    private var watcher: Task<Void, Never>?

    init(store: PermissionStore) {
        self.store = store
        watcher = Task { [weak self] in
            let changes = await store.changes()
            await self?.reload()
            for await _ in changes { await self?.reload() }
        }
    }

    func rows(in group: ToolGroup) -> [Row] { rows.filter { $0.spec.group == group } }

    func set(_ permission: Permission, for tool: String) {
        // Update the screen right away; the store's change stream then confirms (or corrects) it.
        if let index = rows.firstIndex(where: { $0.id == tool }) { rows[index].permission = permission }
        let store = store
        Task { try? await store.set(permission, for: tool) }
    }

    private func reload() async {
        let snapshot = await store.snapshot()
        rows = ToolCatalog.all.map { Row(spec: $0, permission: snapshot[$0.name] ?? .deny) }
    }
}
