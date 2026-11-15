import Foundation
import Observation

public enum VolumeFilter: String, CaseIterable, Sendable {
    case all, named, anonymous
}

@MainActor @Observable
public final class VolumesStore {
    public private(set) var all: [VolumeSummary] = []
    public var selectedID: String?
    public var selectedIDs: Set<String> = []
    public var searchText = ""
    public var filter: VolumeFilter = .all
    public var lastError: String?
    public private(set) var mountedVolumes: Set<String> = []
    public private(set) var mountingVolumes: Set<String> = []

    private let clientProvider: @MainActor () -> (any DockerOperations)?
    private let webdavService: VolumeWebDAVService
    private let openURL: @MainActor (URL) -> Void

    public init(
        clientProvider: @MainActor @escaping () -> (any DockerOperations)? = { nil },
        webdavService: VolumeWebDAVService = .shared,
        openURL: @MainActor @escaping (URL) -> Void = { _ in }
    ) {
        self.clientProvider = clientProvider
        self.webdavService = webdavService
        self.openURL = openURL
    }

    private var activeSocketPath: String? {
        (clientProvider() as? DockerClient)?.socketPath ?? DockerSocket.discover()
    }

    public var volumes: [VolumeSummary] { all }
    public var count: Int { all.count }
    public var selected: VolumeSummary? { all.first { $0.name == selectedID } }

    nonisolated public static func isAnonymousVolume(_ name: String) -> Bool {
        name.count == 64 && name.allSatisfy(\.isHexDigit)
    }

    public var filteredVolumes: [VolumeSummary] {
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

    public func refresh() async {
        guard let client = clientProvider() else {
            all = []
            selectedID = nil
            selectedIDs.removeAll()
            return
        }
        do {
            all = try await client.listVolumes()
            mountedVolumes = webdavService.mountedVolumeNames()
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

    public func openInFinder(name: String) async {
        guard !mountingVolumes.contains(name) else { return }
        mountingVolumes.insert(name)
        defer { mountingVolumes.remove(name) }

        do {
            let info = try await webdavService.mount(volumeName: name, socketPath: activeSocketPath)
            mountedVolumes = webdavService.mountedVolumeNames()
            lastError = nil
            openURL(info.mountPoint)
        } catch {
            lastError = error.localizedDescription
            mountedVolumes = webdavService.mountedVolumeNames()
        }
    }

    public func unmount(name: String) async {
        await webdavService.unmount(volumeName: name, socketPath: activeSocketPath)
        mountedVolumes = webdavService.mountedVolumeNames()
    }

    public func remove(name: String, force: Bool = false) async {
        await remove(names: [name], force: force)
    }

    public func remove(names: Set<String>, force: Bool = false) async {
        guard !names.isEmpty else { return }
        guard let client = clientProvider() else {
            lastError = "Docker client is not connected"
            return
        }
        var errors: [String] = []
        let socketPath = activeSocketPath
        for name in names {
            if mountedVolumes.contains(name) {
                await webdavService.unmount(volumeName: name, socketPath: socketPath)
            }
            do {
                try await client.removeVolume(name, force: force)
            } catch {
                errors.append(error.localizedDescription)
            }
        }
        mountedVolumes = webdavService.mountedVolumeNames()
        selectedIDs.subtract(names)
        lastError = errors.isEmpty ? nil : errors.joined(separator: "\n")
        await refresh()
    }

    public func prune() async {
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
