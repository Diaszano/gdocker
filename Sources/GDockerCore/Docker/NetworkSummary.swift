import Foundation

public struct NetworkSummary: Identifiable, Sendable, Codable, Equatable {
    public let id: String
    public let name: String
    public let driver: String
    public let scope: String
    public let containerCount: Int

    private struct DummyEndpoint: Decodable {}

    enum CodingKeys: String, CodingKey {
        case id = "Id", altId = "id"
        case name = "Name", altName = "name"
        case driver = "Driver", altDriver = "driver"
        case scope = "Scope", altScope = "scope"
        case containers = "Containers"
        case containerCount
    }

    public init(id: String, name: String, driver: String, scope: String, containerCount: Int) {
        self.id = id
        self.name = name
        self.driver = driver
        self.scope = scope
        self.containerCount = containerCount
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
            ?? c.decode(String.self, forKey: .altId)
        name = try c.decodeIfPresent(String.self, forKey: .name)
            ?? c.decode(String.self, forKey: .altName)
        driver = try c.decodeIfPresent(String.self, forKey: .driver)
            ?? c.decode(String.self, forKey: .altDriver)
        scope = try c.decodeIfPresent(String.self, forKey: .scope)
            ?? c.decode(String.self, forKey: .altScope)
        if let count = try c.decodeIfPresent(Int.self, forKey: .containerCount) {
            containerCount = count
        } else if let containers = try c.decodeIfPresent([String: DummyEndpoint].self, forKey: .containers) {
            containerCount = containers.count
        } else {
            containerCount = 0
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(driver, forKey: .driver)
        try c.encode(scope, forKey: .scope)
        try c.encode(containerCount, forKey: .containerCount)
    }
}
