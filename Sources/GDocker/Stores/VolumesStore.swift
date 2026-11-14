import Foundation
import GDockerCore
import Observation

enum VolumeFilter: String, CaseIterable, Sendable {
    case all, named, anonymous
}

@MainActor @Observable
final class VolumesStore {
    private(set) var all: [VolumeSummary] = []
    var selectedID: String?
    var selectedIDs: Set<String> = []
    var searchText = ""
    var filter: VolumeFilter = .all
    var lastError: String?

    private let clientProvider: @MainActor () -> (any DockerOperations)?

    init(clientProvider: @MainActor @escaping () -> (any DockerOperations)? = { nil }) {
        self.clientProvider = clientProvider
    }

    convenience init(client: @MainActor @escaping () -> DockerClient?) {
        self.init(clientProvider: { client() })
    }

    convenience init(store: ContainersStore) {
        self.init(clientProvider: { store.client })
    }

    var volumes: [VolumeSummary] { all }
    var count: Int { all.count }
    var selected: VolumeSummary? { all.first { $0.name == selectedID } }

    nonisolated static func isAnonymousVolume(_ name: String) -> Bool {
        name.count == 64 && name.allSatisfy(\.isHexDigit)
    }

    var filteredVolumes: [VolumeSummary] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return all.filter { volume in
            switch filter {
            case .all: break
            case .named:
                if Self.isAnonymousVolume(volume.name) { return false }
            case .anonymous:
                if !Self.isAnonymousVolume(volume.name) { return false }
            }
            guard !query.isEmpty else { return true }
            return volume.name.localizedCaseInsensitiveContains(query)
                || volume.driver.localizedCaseInsensitiveContains(query)
        }
    }

    func refresh() async {
        guard let client = clientProvider() else {
            all = []
            selectedID = nil
            selectedIDs.removeAll()
            return
        }
        do {
            all = try await client.listVolumes()
            selectedIDs.formIntersection(Set(all.map(\.name)))
            if let selectedID, !all.contains(where: { $0.name == selectedID }) {
                self.selectedID = nil
            }
        } catch {
            lastError = error.localizedDescription
            all = []
            selectedID = nil
            selectedIDs.removeAll()
        }
    }

    func remove(name: String, force: Bool = false) async {
        await remove(names: [name], force: force)
    }

    func remove(names: Set<String>, force: Bool = false) async {
        guard !names.isEmpty else { return }
        guard let client = clientProvider() else {
            lastError = "Docker client is not connected"
            return
        }
        var errors: [String] = []
        for name in names {
            do {
                try await client.removeVolume(name, force: force)
            } catch {
                errors.append(error.localizedDescription)
            }
        }
        selectedIDs.subtract(names)
        lastError = errors.isEmpty ? nil : errors.joined(separator: "\n")
        await refresh()
    }

    func remove(id: String, force: Bool = false) async {
        await remove(name: id, force: force)
    }

    func prune() async {
        guard let client = clientProvider() else {
            lastError = "Docker client is not connected"
            return
        }
        do {
            _ = try await client.pruneVolumes()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        await refresh()
    }
}
