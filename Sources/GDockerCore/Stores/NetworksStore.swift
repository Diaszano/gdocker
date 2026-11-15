import Foundation
import Observation

public enum NetworkFilter: String, CaseIterable, Sendable {
    case all, custom, system
}

@MainActor @Observable
public final class NetworksStore {
    public private(set) var all: [NetworkSummary] = []
    public var selectedID: String?
    public var selectedIDs: Set<String> = []
    public var searchText = ""
    public var filter: NetworkFilter = .all
    public var lastError: String?

    private let clientProvider: @MainActor () -> (any DockerOperations)?

    public init(clientProvider: @MainActor @escaping () -> (any DockerOperations)? = { nil }) {
        self.clientProvider = clientProvider
    }

    public var networks: [NetworkSummary] { all }
    public var count: Int { all.count }
    public var selected: NetworkSummary? { all.first { $0.id == selectedID } }

    nonisolated public static func isDefaultNetworkName(_ name: String) -> Bool {
        ["bridge", "host", "none"].contains(name.lowercased())
    }

    public var filteredNetworks: [NetworkSummary] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return all.filter { network in
            let isDefault = Self.isDefaultNetworkName(network.name)
            switch filter {
            case .all: break
            case .custom:
                if isDefault { return false }
            case .system:
                if !isDefault { return false }
            }
            guard !query.isEmpty else { return true }
            return network.name.localizedCaseInsensitiveContains(query)
                || network.driver.localizedCaseInsensitiveContains(query)
                || network.id.localizedCaseInsensitiveContains(query)
        }
    }

    public func refresh() async {
        guard let client = clientProvider() else {
            all = []
            selectedID = nil
            selectedIDs.removeAll()
            return
        }
        do {
            all = try await client.listNetworks()
            let removableIDs = Set(all.filter { !Self.isDefaultNetworkName($0.name) }.map(\.id))
            selectedIDs.formIntersection(removableIDs)
            if let selectedID, !all.contains(where: { $0.id == selectedID }) {
                self.selectedID = nil
            }
        } catch {
            lastError = error.localizedDescription
            all = []
            selectedID = nil
            selectedIDs.removeAll()
        }
    }

    public func remove(id: String) async {
        await remove(ids: [id])
    }

    public func remove(ids: Set<String>) async {
        let targets = ids.filter { id in
            guard let net = all.first(where: { $0.id == id }) else { return true }
            return !Self.isDefaultNetworkName(net.name)
        }
        guard !targets.isEmpty else { return }
        guard let client = clientProvider() else {
            lastError = "Docker client is not connected"
            return
        }
        var errors: [String] = []
        for id in targets {
            do {
                try await client.removeNetwork(id)
            } catch {
                errors.append(error.localizedDescription)
            }
        }
        selectedIDs.subtract(targets)
        lastError = errors.isEmpty ? nil : errors.joined(separator: "\n")
        await refresh()
    }

    public func prune() async {
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
