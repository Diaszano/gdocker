import Foundation
import GDockerCore
import Observation

@MainActor @Observable
final class NetworksStore {
    private(set) var all: [NetworkSummary] = []
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

    var networks: [NetworkSummary] { all }
    var count: Int { all.count }
    var selected: NetworkSummary? { all.first { $0.id == selectedID } }

    var filteredNetworks: [NetworkSummary] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return all }
        return all.filter { network in
            network.name.localizedCaseInsensitiveContains(query)
                || network.driver.localizedCaseInsensitiveContains(query)
                || network.id.localizedCaseInsensitiveContains(query)
        }
    }

    func refresh() async {
        guard let client = clientProvider() else {
            all = []
            selectedID = nil
            return
        }
        do {
            all = try await client.listNetworks()
            if let selectedID, !all.contains(where: { $0.id == selectedID }) {
                self.selectedID = nil
            }
        } catch {
            lastError = error.localizedDescription
            all = []
            selectedID = nil
        }
    }

    func remove(id: String) async {
        guard let client = clientProvider() else {
            lastError = "Docker client is not connected"
            return
        }
        do {
            try await client.removeNetwork(id)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        await refresh()
    }

    func prune() async {
        guard let client = clientProvider() else {
            lastError = "Docker client is not connected"
            return
        }
        do {
            _ = try await client.pruneNetworks()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        await refresh()
    }
}
