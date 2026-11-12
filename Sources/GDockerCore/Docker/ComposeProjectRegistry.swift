import Foundation

public actor ComposeProjectRegistry {
    public static var defaultFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GDocker")
            .appendingPathComponent("compose_projects.json")
    }

    private let fileURL: URL
    private var projectRecords: [String: ComposeProjectRecord]

    public init(fileURL: URL? = nil) {
        let resolvedURL = fileURL ?? Self.defaultFileURL
        self.fileURL = resolvedURL
        self.projectRecords = Self.loadRecords(from: resolvedURL)
    }

    // MARK: - Ingest

    public func ingest(_ containers: [ContainerSummary]) async {
        var modified = false

        for container in containers {
            guard let rawProject = container.composeProject?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawProject.isEmpty else {
                continue
            }

            let existing = projectRecords[rawProject]

            let rawWorkingDir = (container.labels["com.docker.compose.project.working_dir"] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let workingDir = !rawWorkingDir.isEmpty ? rawWorkingDir : (existing?.workingDir ?? "")

            let rawConfigFiles = (container.labels["com.docker.compose.project.config_files"] ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let configFiles = !rawConfigFiles.isEmpty ? rawConfigFiles : (existing?.configFiles ?? [])

            var serviceNamesSet = Set(existing?.serviceNames ?? [])
            let rawService = (container.labels["com.docker.compose.service"] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let serviceName = !rawService.isEmpty ? rawService : container.name
            if !serviceName.isEmpty {
                serviceNamesSet.insert(serviceName)
            }

            let updatedRecord = ComposeProjectRecord(
                name: rawProject,
                workingDir: workingDir,
                configFiles: configFiles,
                serviceNames: Array(serviceNamesSet).sorted(),
                lastSeen: Date()
            )

            projectRecords[rawProject] = updatedRecord
            modified = true
        }

        if modified {
            persist()
        }
    }

    public func ingest(containers: [ContainerSummary]) async {
        await ingest(containers)
    }

    // MARK: - Remove

    public func removeProject(named name: String) async {
        guard projectRecords.removeValue(forKey: name) != nil else { return }
        persist()
    }

    // MARK: - Records

    public func records() async -> [ComposeProjectRecord] {
        Array(projectRecords.values).sorted { $0.name < $1.name }
    }

    // MARK: - Projects

    public func projects(containers: [ContainerSummary]) async -> [ComposeProject] {
        await ingest(containers)

        var result: [ComposeProject] = []

        for record in projectRecords.values {
            let matchingContainers = containers.filter {
                $0.composeProject?.trimmingCharacters(in: .whitespacesAndNewlines) == record.name
            }

            if matchingContainers.isEmpty {
                let services = record.serviceNames.sorted().map {
                    ComposeServiceSummary(name: $0, containerID: nil, state: nil, statusKind: nil)
                }
                result.append(ComposeProject(
                    name: record.name,
                    workingDir: record.workingDir,
                    configFiles: record.configFiles,
                    services: services,
                    status: .down
                ))
            } else {
                var services: [ComposeServiceSummary] = []
                var seenServices = Set<String>()

                for container in matchingContainers {
                    let rawService = (container.labels["com.docker.compose.service"] ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let serviceName = !rawService.isEmpty ? rawService : container.name
                    seenServices.insert(serviceName)
                    services.append(ComposeServiceSummary(
                        name: serviceName,
                        containerID: container.id,
                        state: container.state,
                        statusKind: container.statusKind
                    ))
                }

                // Add any known serviceNames not currently represented by a container
                for serviceName in record.serviceNames where !seenServices.contains(serviceName) {
                    services.append(ComposeServiceSummary(
                        name: serviceName,
                        containerID: nil,
                        state: nil,
                        statusKind: nil
                    ))
                }

                services.sort { $0.name < $1.name }

                let allServicesHaveContainer = !services.contains { $0.containerID == nil }
                let status: ComposeStatus
                if allServicesHaveContainer && services.allSatisfy({ $0.statusKind == .running }) {
                    status = .running
                } else if allServicesHaveContainer && services.allSatisfy({ $0.statusKind == .stopped || $0.statusKind == .failed }) {
                    status = .stopped
                } else {
                    status = .partiallyRunning
                }

                result.append(ComposeProject(
                    name: record.name,
                    workingDir: record.workingDir,
                    configFiles: record.configFiles,
                    services: services,
                    status: status
                ))
            }
        }

        return result.sorted { $0.name < $1.name }
    }

    // MARK: - Persistence

    private func persist() {
        let list = Array(projectRecords.values).sorted { $0.name < $1.name }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(list)
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Silently handle persistence failures (e.g. read-only filesystem in tests)
        }
    }

    private static func loadRecords(from url: URL) -> [String: ComposeProjectRecord] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let list = try? decoder.decode([ComposeProjectRecord].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: list.map { ($0.name, $0) })
    }
}
