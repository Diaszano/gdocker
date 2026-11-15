import Foundation

public struct ToolOutput: Sendable, Equatable {
    public let text: String
    public let isError: Bool

    public init(text: String, isError: Bool) { self.text = text; self.isError = isError }
}

/// Runs one MCP tool call: validates the arguments, applies the Allow/Ask/Deny rule (asking the user when needed),
/// resolves the container, runs the Docker operation and records what happened. Nothing reaches Docker unless the
/// rule or the user allowed it.
public actor ToolRouter {
    private let docker: @Sendable () async -> (any DockerOperations)?
    private let compose: (@Sendable () async -> (any ComposeOperations)?)?
    private let registry: ComposeProjectRegistry?
    private let permissions: PermissionStore
    private let prompter: any ApprovalPrompter
    private let activity: ActivityLog
    private let approvalTimeout: Duration

    public init(
        docker: @escaping @Sendable () async -> (any DockerOperations)?,
        compose: (@Sendable () async -> (any ComposeOperations)?)? = nil,
        registry: ComposeProjectRegistry? = nil,
        permissions: PermissionStore,
        prompter: any ApprovalPrompter,
        activity: ActivityLog,
        approvalTimeout: Duration = .seconds(120)
    ) {
        self.docker = docker
        self.compose = compose
        self.registry = registry
        self.permissions = permissions
        self.prompter = prompter
        self.activity = activity
        self.approvalTimeout = approvalTimeout
    }

    public func call(_ tool: String, arguments raw: [String: JSONValue], client: String) async -> ToolOutput {
        guard let spec = ToolCatalog.spec(named: tool) else {
            return await finish(client, tool, "", .error, "Unknown tool '\(tool)'.", isError: true)
        }
        let args: ToolArguments
        do {
            args = try ToolArguments(spec: spec, raw: raw)
        } catch {
            let message = (error as? ToolFailure)?.message ?? "\(error)"
            return await finish(client, tool, "", .error, message, isError: true)
        }
        func done(_ outcome: ActivityEntry.Outcome, _ text: String, isError: Bool) async -> ToolOutput {
            await finish(client, tool, args.summary, outcome, text, isError: isError)
        }

        let rule = await permissions.permission(for: tool)
        if rule == .deny {
            return await done(.denied, "Blocked: the user set \(tool) to Deny in gdocker Permissions.", isError: true)
        }
        guard let docker = await docker() else {
            return await done(
                .error, "Docker is not connected. Open GDocker and make sure Docker is running.", isError: true)
        }

        do {
            let target = try await resolveTarget(of: spec, args, docker)
            var outcome = ActivityEntry.Outcome.allowed
            if rule == .ask {
                let request = ApprovalRequest(
                    client: client, tool: tool, arguments: displayArguments(spec, args, target),
                    reason: args.reason, allowsAlways: spec.allowsAlways)
                guard let decision = await decide(request) else {
                    return await done(
                        .denied, "Approval timed out: the user did not respond in time, so \(tool) was not run.",
                        isError: true)
                }
                switch decision {
                case .deny:
                    return await done(.denied, "The user denied this request: \(tool) was not run.", isError: true)
                case .allowAlways:
                    if spec.allowsAlways { try? await permissions.set(.allow, for: tool) }
                    outcome = .approved
                case .allowOnce:
                    outcome = .approved
                }
            }
            return await done(outcome, try await run(tool, args, target, docker), isError: false)
        } catch let failure as ToolFailure {
            return await done(.error, failure.message, isError: true)
        } catch let composeError as ComposeError {
            return await done(.error, composeError.errorDescription ?? "\(composeError)", isError: true)
        } catch let dockerError as DockerError {
            return await done(.error, dockerError.errorDescription ?? "\(dockerError)", isError: true)
        } catch {
            return await done(.error, (error as? LocalizedError)?.errorDescription ?? "\(error)", isError: true)
        }
    }

    // MARK: - Approval

    /// `nil` when the user did not answer within the timeout. The prompter must honour cancellation (the
    /// `ApprovalQueue` does), otherwise the race below cannot end.
    private func decide(_ request: ApprovalRequest) async -> ApprovalDecision? {
        let prompter = prompter
        let timeout = approvalTimeout
        return await withTaskGroup(of: ApprovalDecision?.self) { group in
            group.addTask { await prompter.decide(request) }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private func displayArguments(
        _ spec: ToolSpec, _ args: ToolArguments, _ target: ContainerSummary?
    ) -> [ApprovalArgument] {
        var shown: [ApprovalArgument] = []
        if let target { shown.append(ApprovalArgument(name: "container", value: target.name)) }
        for parameter in spec.parameters where parameter.name != "container" {
            switch parameter.kind {
            case .stringArray:
                if let argv = args.strings(parameter.name) {
                    shown.append(ApprovalArgument(name: parameter.name, value: ToolArguments.displayCommand(argv)))
                }
            case .string:
                if let text = args.string(parameter.name) { shown.append(ApprovalArgument(name: parameter.name, value: text)) }
            case .integer:
                if let number = args.int(parameter.name) {
                    shown.append(ApprovalArgument(name: parameter.name, value: String(number)))
                }
            case .boolean:
                if let flag = args.bool(parameter.name) {
                    if parameter.name == "remove_volumes" {
                        if flag {
                            shown.append(ApprovalArgument(name: parameter.name, value: "true"))
                        }
                    } else {
                        shown.append(ApprovalArgument(name: parameter.name, value: String(flag)))
                    }
                }
            }
        }
        return shown
    }

    // MARK: - Container resolution

    private func resolveTarget(
        of spec: ToolSpec, _ args: ToolArguments, _ docker: any DockerOperations
    ) async throws -> ContainerSummary? {
        guard spec.parameters.contains(where: { $0.name == "container" }), let reference = args.string("container")
        else { return nil }
        let containers = try await docker.listContainers()
        if let exact = containers.first(where: { $0.name == reference }) { return exact }
        let byPrefix = containers.filter { $0.id.hasPrefix(reference) }
        switch byPrefix.count {
        case 1: return byPrefix[0]
        case 0: throw ToolFailure("No container matches '\(reference)'.")
        default:
            let names = byPrefix.map(\.name).joined(separator: ", ")
            throw ToolFailure("Ambiguous container '\(reference)': matches \(names). Use the full name or a longer id.")
        }
    }

    // MARK: - Execution

    private func run(
        _ tool: String, _ args: ToolArguments, _ target: ContainerSummary?, _ docker: any DockerOperations
    ) async throws -> String {
        switch tool {
        case "list_containers":
            let showAll = args.bool("all") ?? true
            let containers = try await docker.listContainers().filter { showAll || $0.isActive }
            return Self.jsonText(containers.map(Self.describe))
        case "inspect_container":
            return Masking.maskEnv(inInspectJSON: try await docker.inspect(try need(target).id).rawJSON)
        case "get_logs":
            let tail = min(max(args.int("tail") ?? 100, 1), 2000)
            let timestamps = args.bool("timestamps") ?? false
            let lines = try await docker.recentLogs(try need(target).id, tail: tail, timestamps: timestamps)
            guard timestamps else {
                return lines.map(\.text).joined(separator: "\n")
            }
            let formatter = Self.makeISOFormatter()
            return lines.map { line in
                line.timestamp.map { "\(formatter.string(from: $0)) \(line.text)" } ?? line.text
            }.joined(separator: "\n")
        case "get_stats":
            let sample = try await docker.statsOnce(try need(target).id)
            return Self.jsonText([
                "cpu_percent": (sample.cpuPercent * 100).rounded() / 100,
                "memory_used_bytes": Int(clamping: sample.memoryUsed),
                "memory_limit_bytes": Int(clamping: sample.memoryLimit),
                "net_rx_bytes": Int(clamping: sample.netRx),
                "net_tx_bytes": Int(clamping: sample.netTx),
            ] as [String: Any])
        case "get_container_env":
            let env = try await docker.inspect(try need(target).id).details.config.env
            return env.isEmpty ? "(no environment variables)" : env.joined(separator: "\n")
        case "start_container":
            let container = try need(target)
            try await docker.start(container.id)
            return "Started \(container.name)"
        case "restart_container":
            let container = try need(target)
            try await docker.restart(container.id)
            return "Restarted \(container.name)"
        case "stop_container":
            let container = try need(target)
            try await docker.stop(container.id)
            return "Stopped \(container.name)"
        case "exec_in_container":
            let container = try need(target)
            let result = try await docker.exec(container.id, command: args.strings("command") ?? [])
            return Self.jsonText([
                "exit_code": result.exitCode, "stdout": result.stdout, "stderr": result.stderr,
                "truncated": result.truncated,
            ] as [String: Any])
        case "remove_container":
            let container = try need(target)
            try await docker.remove(container.id, force: args.bool("force") ?? false)
            return "Removed \(container.name)"
        case "list_images":
            let images = try await docker.listImages()
            return Self.jsonText(images.map(Self.describe))
        case "list_volumes":
            let volumes = try await docker.listVolumes()
            return Self.jsonText(volumes.map(Self.describe))
        case "list_networks":
            let networks = try await docker.listNetworks()
            return Self.jsonText(networks.map(Self.describe))
        case "remove_image":
            guard let image = args.string("image") else {
                throw ToolFailure("Missing required argument 'image'.")
            }
            let force = args.bool("force") ?? false
            try await docker.removeImage(image, force: force)
            return "Removed \(image)"
        case "remove_volume":
            guard let volume = args.string("volume") else {
                throw ToolFailure("Missing required argument 'volume'.")
            }
            let force = args.bool("force") ?? false
            try await docker.removeVolume(volume, force: force)
            return "Removed \(volume)"
        case "remove_network":
            guard let network = args.string("network") else {
                throw ToolFailure("Missing required argument 'network'.")
            }
            let defaultNetworks: Set<String> = ["bridge", "host", "none"]
            if defaultNetworks.contains(network.lowercased()) {
                throw ToolFailure("Predefined network '\(network)' cannot be removed.")
            }
            let networks = try await docker.listNetworks()
            let match = networks.first(where: { $0.id == network || $0.id.hasPrefix(network) || $0.name == network })
            if let match, defaultNetworks.contains(match.name.lowercased()) {
                throw ToolFailure("Predefined network '\(match.name)' cannot be removed.")
            }
            try await docker.removeNetwork(match?.id ?? network)
            return "Removed \(network)"
        case "system_prune":
            let all = args.bool("all") ?? false
            let volumes = args.bool("volumes") ?? false
            let report = try await docker.systemPrune(all: all, volumes: volumes)
            return Self.jsonText(Self.describe(report))
        case "list_compose_projects", "compose_up", "compose_down":
            guard let composeFactory = compose, let runner = await composeFactory(), await runner.isComposeAvailable() else {
                throw ToolFailure("Docker Compose is not available. Ensure Docker Compose is installed.")
            }
            if let registry {
                if let containers = try? await docker.listContainers() {
                    await registry.ingest(containers)
                }
            }
            switch tool {
            case "list_compose_projects":
                let containers = (try? await docker.listContainers()) ?? []
                let projects = await registry?.projects(containers: containers) ?? []
                return Self.jsonText(projects.map(Self.describe))
            case "compose_up":
                guard let projectName = args.string("project") else {
                    throw ToolFailure("Missing required argument 'project'.")
                }
                let records = await registry?.records() ?? []
                guard let record = records.first(where: { $0.name == projectName }) else {
                    throw ToolFailure("Unknown compose project '\(projectName)'. Run list_compose_projects to see known projects.")
                }
                let output = try await runner.composeUp(
                    project: record.name,
                    workingDir: record.workingDir,
                    configFiles: record.configFiles
                )
                let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? "Started compose project \(projectName)" : output
            case "compose_down":
                guard let projectName = args.string("project") else {
                    throw ToolFailure("Missing required argument 'project'.")
                }
                let removeVolumes = args.bool("remove_volumes") ?? false
                let records = await registry?.records() ?? []
                guard let record = records.first(where: { $0.name == projectName }) else {
                    throw ToolFailure("Unknown compose project '\(projectName)'. Run list_compose_projects to see known projects.")
                }
                let output = try await runner.composeDown(
                    project: record.name,
                    workingDir: record.workingDir,
                    configFiles: record.configFiles,
                    removeVolumes: removeVolumes
                )
                let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? "Stopped compose project \(projectName)" : output
            default:
                fatalError("Unreachable compose tool \(tool)")
            }
        default:
            throw ToolFailure("Tool '\(tool)' is not implemented.")
        }
    }

    private func need(_ target: ContainerSummary?) throws -> ContainerSummary {
        guard let target else { throw ToolFailure("Missing required argument 'container'.") }
        return target
    }

    // MARK: - Formatting

    private func finish(
        _ client: String, _ tool: String, _ arguments: String, _ outcome: ActivityEntry.Outcome,
        _ text: String, isError: Bool
    ) async -> ToolOutput {
        await activity.record(
            client: client, tool: tool, arguments: arguments, outcome: outcome,
            detail: isError ? text : nil)
        return ToolOutput(text: text, isError: isError)
    }

    private static func describe(_ container: ContainerSummary) -> [String: Any] {
        var ports: [String] = []
        for port in container.ports {
            let text = port.publicPort.map { "\($0)->\(port.privatePort)/\(port.type)" } ?? "\(port.privatePort)/\(port.type)"
            if !ports.contains(text) { ports.append(text) }
        }
        return [
            "id": String(container.id.prefix(12)), "name": container.name, "image": container.image,
            "state": container.state, "status": container.status,
            "project": container.composeProject ?? NSNull(), "ports": ports,
        ]
    }

    private static func describe(_ image: ImageSummary) -> [String: Any] {
        let cleanId = image.id.replacingOccurrences(of: "sha256:", with: "")
        return [
            "id": String(cleanId.prefix(12)),
            "repo_tags": image.repoTags,
            "size_bytes": image.size,
            "created": image.created,
        ]
    }

    private static func describe(_ volume: VolumeSummary) -> [String: Any] {
        var dict: [String: Any] = [
            "name": volume.name,
            "driver": volume.driver,
            "scope": volume.scope,
        ]
        if let createdAt = volume.createdAt {
            dict["created_at"] = createdAt
        }
        return dict
    }

    private static func describe(_ network: NetworkSummary) -> [String: Any] {
        return [
            "id": String(network.id.prefix(12)),
            "name": network.name,
            "driver": network.driver,
            "scope": network.scope,
            "container_count": network.containerCount,
        ]
    }

    private static func describe(_ report: PruneReport) -> [String: Any] {
        return [
            "containers_deleted": report.containersDeleted,
            "images_deleted": report.imagesDeleted,
            "networks_deleted": report.networksDeleted,
            "volumes_deleted": report.volumesDeleted,
            "space_reclaimed_bytes": report.spaceReclaimed,
        ]
    }

    private static func describe(_ project: ComposeProject) -> [String: Any] {
        let services: [[String: Any]] = project.services.map { service in
            [
                "name": service.name,
                "container_id": service.containerID.map { String($0.prefix(12)) } ?? NSNull(),
                "state": service.state ?? NSNull(),
                "status": service.statusKind?.rawValue ?? NSNull(),
            ]
        }
        return [
            "name": project.name,
            "status": project.status.rawValue,
            "working_dir": project.workingDir,
            "config_files": project.configFiles,
            "services": services,
        ]
    }

    private static func jsonText(_ object: Any) -> String {
        let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        return String(decoding: data ?? Data(), as: UTF8.self)
    }

    private static func makeISOFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}
