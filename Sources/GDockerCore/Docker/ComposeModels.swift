import Foundation

public struct ComposeServiceSummary: Sendable, Codable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    public let containerID: String?
    public let state: String?
    public let statusKind: StatusKind?

    public init(name: String, containerID: String? = nil, state: String? = nil, statusKind: StatusKind? = nil) {
        self.name = name
        self.containerID = containerID
        self.state = state
        self.statusKind = statusKind
    }
}

public enum ComposeStatus: String, Sendable, Codable, Equatable {
    case running
    case partiallyRunning
    case stopped
    case down
}

public struct ComposeProject: Sendable, Codable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    public let workingDir: String
    public let configFiles: [String]
    public let services: [ComposeServiceSummary]
    public let status: ComposeStatus

    public init(
        name: String,
        workingDir: String,
        configFiles: [String],
        services: [ComposeServiceSummary],
        status: ComposeStatus
    ) {
        self.name = name
        self.workingDir = workingDir
        self.configFiles = configFiles
        self.services = services
        self.status = status
    }
}

public struct ComposeProjectRecord: Sendable, Codable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    public let workingDir: String
    public let configFiles: [String]
    public let serviceNames: [String]
    public let lastSeen: Date

    public init(
        name: String,
        workingDir: String,
        configFiles: [String],
        serviceNames: [String],
        lastSeen: Date = Date()
    ) {
        self.name = name
        self.workingDir = workingDir
        self.configFiles = configFiles
        self.serviceNames = serviceNames
        self.lastSeen = lastSeen
    }
}
