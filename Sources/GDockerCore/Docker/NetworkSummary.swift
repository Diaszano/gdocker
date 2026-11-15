import Foundation

public struct NetworkSummary: Identifiable, Sendable, Decodable, Equatable {
    public let id: String
    public let name: String
    public let driver: String
    public let scope: String
    public let containerCount: Int

    private struct DummyEndpoint: Decodable {}

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case driver = "Driver"
        case scope = "Scope"
        case containers = "Containers"
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
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        driver = try c.decode(String.self, forKey: .driver)
        scope = try c.decode(String.self, forKey: .scope)
        containerCount = try c.decodeIfPresent([String: DummyEndpoint].self, forKey: .containers)?.count ?? 0
    }
}
