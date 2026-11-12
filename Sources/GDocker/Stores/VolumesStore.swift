import Foundation
import GDockerCore
import Observation

@MainActor @Observable
final class VolumesStore {
    private(set) var all: [VolumeSummary] = []
    var selectedID: String?
    var searchText = ""
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

    var filteredVolumes: [VolumeSummary] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return all }
        return all.filter { volume in
            volume.name.localizedCaseInsensitiveContains(query)
                || volume.driver.localizedCaseInsensitiveContains(query)
        }
    }

    func refresh() async {
        guard let client = clientProvider() else {
            all = []
            selectedID = nil
            return
        }
        do {
            all = try await client.listVolumes()
            if let selectedID, !all.contains(where: { $0.name == selectedID }) {
                self.selectedID = nil
            }
        } catch {
            lastError = error.localizedDescription
            all = []
            selectedID = nil
        }
    }

    func remove(name: String, force: Bool = false) async {
        guard let client = clientProvider() else {
            lastError = "Docker client is not connected"
            return
        }
        do {
            try await client.removeVolume(name, force: force)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
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
