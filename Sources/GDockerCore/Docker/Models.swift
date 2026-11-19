import Foundation

public enum StatusKind: String, Codable, Sendable, Equatable { case running, transitioning, stopped, failed }

public struct PortBinding: Decodable, Hashable, Sendable {
    public let ip: String?
    public let privatePort: Int
    public let publicPort: Int?
    public let type: String

    enum CodingKeys: String, CodingKey {
        case ip = "IP"
        case privatePort = "PrivatePort"
        case publicPort = "PublicPort"
        case type = "Type"
    }
}

public struct ContainerSummary: Decodable, Identifiable, Hashable, Sendable {
    public let id: String
    public let names: [String]
    public let image: String
    public let state: String
    public let status: String
    public let labels: [String: String]
    public let ports: [PortBinding]
    public let sizeRw: Int64?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case names = "Names"
        case image = "Image"
        case state = "State"
        case status = "Status"
        case labels = "Labels"
        case ports = "Ports"
        case sizeRw = "SizeRw"
    }

    public init(
        id: String, names: [String], image: String, state: String, status: String,
        labels: [String: String], ports: [PortBinding], sizeRw: Int64? = nil
    ) {
        self.id = id
        self.names = names
        self.image = image
        self.state = state
        self.status = status
        self.labels = labels
        self.ports = ports
        self.sizeRw = sizeRw
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        names = try c.decodeIfPresent([String].self, forKey: .names) ?? []
        image = try c.decode(String.self, forKey: .image)
        state = try c.decode(String.self, forKey: .state)
        status = try c.decode(String.self, forKey: .status)
        labels = try c.decodeIfPresent([String: String].self, forKey: .labels) ?? [:]
        ports = try c.decodeIfPresent([PortBinding].self, forKey: .ports) ?? []
        sizeRw = try c.decodeIfPresent(Int64.self, forKey: .sizeRw)
    }

    public var name: String {
        let first = names.first ?? String(id.prefix(12))
        return first.hasPrefix("/") ? String(first.dropFirst()) : first
    }

    public var composeProject: String? { labels["com.docker.compose.project"] }

    /// Has a live process, so the user can stop it. `created` is not active (it offers Start) even though its dot is orange.
    public var isActive: Bool { ["running", "paused", "restarting"].contains(state) }

    public var statusKind: StatusKind {
        switch state {
        case "running": return .running
        case "restarting", "paused", "created": return .transitioning
        case "exited": return exitCode == 0 ? .stopped : .failed
        default: return .failed
        }
    }

    private var exitCode: Int? {
        guard let range = status.range(of: #"Exited \((\d+)\)"#, options: .regularExpression) else { return nil }
        return Int(status[range].filter(\.isNumber))
    }
}

public struct DockerHostInfo: Sendable, Equatable {
    public let name: String
    public let cpus: Int
    public let cpuPercent: Double?
    public let memUsed: Int64?
    public let memTotal: Int64
    public let diskUsed: Int64?
    public let diskTotal: Int64?
    public let isColima: Bool

    public init(
        name: String,
        cpus: Int,
        cpuPercent: Double? = nil,
        memUsed: Int64? = nil,
        memTotal: Int64,
        diskUsed: Int64? = nil,
        diskTotal: Int64? = nil,
        isColima: Bool = false
    ) {
        self.name = name
        self.cpus = cpus
        self.cpuPercent = cpuPercent
        self.memUsed = memUsed
        self.memTotal = memTotal
        self.diskUsed = diskUsed
        self.diskTotal = diskTotal
        self.isColima = isColima
    }

    public func withUsage(cpuPercent: Double?, memUsed: Int64?) -> DockerHostInfo {
        DockerHostInfo(
            name: name,
            cpus: cpus,
            cpuPercent: cpuPercent,
            memUsed: memUsed,
            memTotal: memTotal,
            diskUsed: diskUsed,
            diskTotal: diskTotal,
            isColima: isColima
        )
    }
}

public enum ContainerStatusFilter: String, CaseIterable, Sendable {
    case all, running, stopped, failed

    public func matches(_ container: ContainerSummary) -> Bool {
        switch self {
        case .all: true
        case .running: container.statusKind == .running || container.statusKind == .transitioning
        case .stopped: container.statusKind == .stopped
        case .failed: container.statusKind == .failed
        }
    }
}

public struct ContainerGroup: Identifiable, Sendable {
    public let project: String?
    public let containers: [ContainerSummary]
    public var id: String { project ?? "" }
}

/// Named projects alphabetically, containers without a project last; containers sorted by name.
public func groupByCompose(_ containers: [ContainerSummary]) -> [ContainerGroup] {
    let byProject = Dictionary(grouping: containers, by: \.composeProject)
    return
        byProject
        .map { ContainerGroup(project: $0.key, containers: $0.value.sorted { $0.name < $1.name }) }
        .sorted { a, b in
            switch (a.project, b.project) {
            case (let x?, let y?): return x < y
            case (nil, _?): return false
            case (_?, nil): return true
            case (nil, nil): return false
            }
        }
}

public struct ContainerDetails: Decodable, Sendable {
    public struct Config: Decodable, Sendable {
        public let image: String
        public let env: [String]
        public let tty: Bool

        enum CodingKeys: String, CodingKey {
            case image = "Image"
            case env = "Env"
            case tty = "Tty"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            image = try c.decode(String.self, forKey: .image)
            env = try c.decodeIfPresent([String].self, forKey: .env) ?? []
            tty = try c.decodeIfPresent(Bool.self, forKey: .tty) ?? false
        }
    }

    public struct State: Decodable, Sendable {
        public let status: String
        public let startedAt: String

        enum CodingKeys: String, CodingKey {
            case status = "Status"
            case startedAt = "StartedAt"
        }
    }

    public let id: String
    public let name: String
    public let config: Config
    public let state: State

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case config = "Config"
        case state = "State"
    }
}
