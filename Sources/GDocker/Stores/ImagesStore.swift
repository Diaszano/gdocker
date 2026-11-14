import Foundation
import GDockerCore
import Observation

enum ImageFilter: String, CaseIterable, Sendable {
    case all, inUse, dangling
}

@MainActor @Observable
final class ImagesStore {
    private(set) var all: [ImageSummary] = []
    var selectedID: String?
    var selectedIDs: Set<String> = []
    var searchText = ""
    var filter: ImageFilter = .all
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

    var images: [ImageSummary] { all }
    var count: Int { all.count }
    var selected: ImageSummary? { all.first { $0.id == selectedID } }

    var filteredImages: [ImageSummary] {
        filteredImages(containers: [])
    }

    func containerUsageCount(for image: ImageSummary, containers: [ContainerSummary]) -> Int {
        let validTags = Set(image.repoTags.filter { $0 != "<none>:<none>" })
        let rawID = image.id.hasPrefix("sha256:") ? String(image.id.dropFirst(7)) : image.id
        let shortID = String(rawID.prefix(12))
        return containers.filter { container in
            validTags.contains(container.image)
                || container.image == image.id
                || container.image == rawID
                || container.image == shortID
        }.count
    }

    func filteredImages(containers: [ContainerSummary]) -> [ImageSummary] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return all.filter { image in
            switch filter {
            case .all: break
            case .inUse:
                if containerUsageCount(for: image, containers: containers) == 0 { return false }
            case .dangling:
                if !(image.repoTags.isEmpty || (image.repoTags.count == 1 && image.repoTags[0] == "<none>:<none>")) {
                    return false
                }
            }
            guard !query.isEmpty else { return true }
            return image.repoTags.contains { $0.localizedCaseInsensitiveContains(query) }
                || image.id.localizedCaseInsensitiveContains(query)
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
            all = try await client.listImages()
            selectedIDs.formIntersection(Set(all.map(\.id)))
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

    func remove(id: String, force: Bool = false) async {
        await remove(ids: [id], force: force)
    }

    func remove(ids: Set<String>, force: Bool = false) async {
        guard !ids.isEmpty else { return }
        guard let client = clientProvider() else {
            lastError = "Docker client is not connected"
            return
        }
        var errors: [String] = []
        for id in ids {
            do {
                try await client.removeImage(id, force: force)
            } catch {
                errors.append(error.localizedDescription)
            }
        }
        selectedIDs.subtract(ids)
        lastError = errors.isEmpty ? nil : errors.joined(separator: "\n")
        await refresh()
    }

    func prune(all: Bool = false) async {
        guard let client = clientProvider() else {
            lastError = "Docker client is not connected"
            return
        }
        do {
            _ = try await client.pruneImages(all: all)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        await refresh()
    }
}
