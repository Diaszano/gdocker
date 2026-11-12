import Foundation

public enum StatusKind: String, Codable, Sendable, Equatable { case running, transitioning, stopped, failed }

public struct PortBinding: Decodable, Hashable, Sendable {
    public let ip: String?
    public let privatePort: Int
    public let publicPort: Int?
    public let type: String

    enum CodingKeys: String, CodingKey {
        case ip = "IP", privatePort = "PrivatePort", publicPort = "PublicPort", type = "Type"
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

    enum CodingKeys: String, CodingKey {
        case id = "Id", names = "Names", image = "Image", state = "State", status = "Status"
        case labels = "Labels", ports = "Ports"
    }

    public init(
        id: String, names: [String], image: String, state: String, status: String,
        labels: [String: String], ports: [PortBinding]
    ) {
        self.id = id; self.names = names; self.image = image; self.state = state
        self.status = status; self.labels = labels; self.ports = ports
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

public struct ContainerGroup: Identifiable, Sendable {
    public let project: String?
    public let containers: [ContainerSummary]
    public var id: String { project ?? "" }
}

/// Named projects alphabetically, containers without a project last; containers sorted by name.
public func groupByCompose(_ containers: [ContainerSummary]) -> [ContainerGroup] {
    let byProject = Dictionary(grouping: containers, by: \.composeProject)
    return byProject
        .map { ContainerGroup(project: $0.key, containers: $0.value.sorted { $0.name < $1.name }) }
        .sorted { a, b in
            switch (a.project, b.project) {
            case let (x?, y?): return x < y
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

        enum CodingKeys: String, CodingKey { case image = "Image", env = "Env", tty = "Tty" }

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

        enum CodingKeys: String, CodingKey { case status = "Status", startedAt = "StartedAt" }
    }

    public let id: String
    public let name: String
    public let config: Config
    public let state: State

    enum CodingKeys: String, CodingKey { case id = "Id", name = "Name", config = "Config", state = "State" }
}
